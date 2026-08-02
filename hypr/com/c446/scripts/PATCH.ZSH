#!/usr/bin/env zsh
set -euo pipefail

src=${1:-./desk-cursor.go}

if [[ ! -f $src ]]; then
    print -u2 -- "desk-cursor source not found: $src"
    exit 1
fi

backup="${src}.bak.$(date +%Y%m%d-%H%M%S)"
cp -- "$src" "$backup"
print -- "Backup: $backup"

python3 - "$src" <<'PYCODE'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()


def matching_brace(source: str, open_index: int) -> int:
    depth = 0
    i = open_index
    state = "code"
    while i < len(source):
        char = source[i]
        following = source[i + 1] if i + 1 < len(source) else ""

        if state == "code":
            if char == "/" and following == "/":
                state = "line_comment"
                i += 2
                continue
            if char == "/" and following == "*":
                state = "block_comment"
                i += 2
                continue
            if char == '"':
                state = "string"
                i += 1
                continue
            if char == "`":
                state = "raw_string"
                i += 1
                continue
            if char == "'":
                state = "rune"
                i += 1
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
            continue

        if state == "line_comment":
            if char == "\n":
                state = "code"
            i += 1
            continue

        if state == "block_comment":
            if char == "*" and following == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue

        if state == "string":
            if char == "\\":
                i += 2
            elif char == '"':
                state = "code"
                i += 1
            else:
                i += 1
            continue

        if state == "raw_string":
            if char == "`":
                state = "code"
            i += 1
            continue

        if state == "rune":
            if char == "\\":
                i += 2
            elif char == "'":
                state = "code"
                i += 1
            else:
                i += 1
            continue

    raise RuntimeError("unclosed Go declaration")


def declaration_span(pattern: str):
    match = re.search(pattern, text, re.MULTILINE)
    if match is None:
        return None
    opening = text.find("{", match.start())
    if opening < 0:
        raise RuntimeError(f"opening brace missing for {pattern}")
    return match.start(), matching_brace(text, opening)


def replace_declaration(pattern: str, replacement: str, required: bool = True):
    global text
    span = declaration_span(pattern)
    if span is None:
        if required:
            raise RuntimeError(f"declaration not found: {pattern}")
        return False
    start, end = span
    text = text[:start] + replacement.rstrip() + text[end:]
    return True


def remove_declaration(pattern: str):
    global text
    span = declaration_span(pattern)
    if span is None:
        return
    start, end = span
    while end < len(text) and text[end] == "\n":
        end += 1
    text = text[:start] + text[end:]

BLOCKS = {
    'PairGeometry': 'type PairGeometry struct {\n\tBoundaryX           float64\n\tLeftRect            Rect\n\tRightRect           Rect\n\tEffectiveLeftScale  float64\n\tEffectiveRightScale float64\n}',
    'Validation': 'type Validation struct {\n\tLeft     Monitor\n\tRight    Monitor\n\tMode     CoordinateMode\n\tGeometry PairGeometry\n}',
    'validateProfile': 'func validateProfile(profile Profile, monitors []Monitor) (Validation, error) {\n\tactive := activeMonitors(monitors)\n\tif len(active) != 2 {\n\t\treturn Validation{}, fmt.Errorf("expected exactly 2 active monitors, found %d", len(active))\n\t}\n\n\tfor _, monitor := range active {\n\t\tif mirrorEnabled(monitor) {\n\t\t\treturn Validation{}, fmt.Errorf("monitor %s mirrors %s", monitor.Name, monitor.MirrorOf)\n\t\t}\n\t\tif monitor.Transform != 0 {\n\t\t\treturn Validation{}, fmt.Errorf("monitor %s has unsupported transform %d", monitor.Name, monitor.Transform)\n\t\t}\n\t\tif monitor.PhysicalWidth <= 0 || monitor.PhysicalHeight <= 0 {\n\t\t\treturn Validation{}, fmt.Errorf("monitor %s has invalid physical dimensions", monitor.Name)\n\t\t}\n\t\tif monitor.Scale <= 0 {\n\t\t\treturn Validation{}, fmt.Errorf("monitor %s has invalid scale %.3f", monitor.Name, monitor.Scale)\n\t\t}\n\t}\n\n\tvar left, right *Monitor\n\tfor i := range active {\n\t\tmonitor := &active[i]\n\t\tif monitorIdentityMatches(profile.Left, *monitor) {\n\t\t\tleft = monitor\n\t\t}\n\t\tif monitorIdentityMatches(profile.Right, *monitor) {\n\t\t\tright = monitor\n\t\t}\n\t}\n\tif left == nil {\n\t\treturn Validation{}, errors.New("saved left monitor identity is not present")\n\t}\n\tif right == nil {\n\t\treturn Validation{}, errors.New("saved right monitor identity is not present")\n\t}\n\tif left.Name == right.Name {\n\t\treturn Validation{}, errors.New("left and right profile identities resolved to the same monitor")\n\t}\n\n\tif err := validateMonitorMode(profile.Left, *left); err != nil {\n\t\treturn Validation{}, fmt.Errorf("left monitor: %w", err)\n\t}\n\tif err := validateMonitorMode(profile.Right, *right); err != nil {\n\t\treturn Validation{}, fmt.Errorf("right monitor: %w", err)\n\t}\n\tif left.X >= right.X {\n\t\treturn Validation{}, fmt.Errorf("saved left monitor %s is not left of %s", left.Name, right.Name)\n\t}\n\n\tmode := inferCoordinateMode(*left, *right)\n\tif profile.CoordinateMode != "" && mode != profile.CoordinateMode {\n\t\treturn Validation{}, fmt.Errorf("coordinate mode changed from %s to %s", profile.CoordinateMode, mode)\n\t}\n\tif absInt((right.X-left.X)-profile.RelativeX) > 3 || absInt((right.Y-left.Y)-profile.RelativeY) > 3 {\n\t\treturn Validation{}, fmt.Errorf(\n\t\t\t"relative layout changed: got (%d,%d), expected (%d,%d)",\n\t\t\tright.X-left.X,\n\t\t\tright.Y-left.Y,\n\t\t\tprofile.RelativeX,\n\t\t\tprofile.RelativeY,\n\t\t)\n\t}\n\n\tgeometry, err := pairGeometry(*left, *right, mode)\n\tif err != nil {\n\t\treturn Validation{}, err\n\t}\n\tif overlapLength(\n\t\tgeometry.LeftRect.Y,\n\t\tgeometry.LeftRect.Y+geometry.LeftRect.H,\n\t\tgeometry.RightRect.Y,\n\t\tgeometry.RightRect.Y+geometry.RightRect.H,\n\t) <= 0 {\n\t\treturn Validation{}, errors.New("monitor rectangles do not overlap vertically")\n\t}\n\n\treturn Validation{Left: *left, Right: *right, Mode: mode, Geometry: geometry}, nil\n}',
    'pairGeometry': 'func pairGeometry(left, right Monitor, mode CoordinateMode) (PairGeometry, error) {\n\tif left.X >= right.X {\n\t\treturn PairGeometry{}, errors.New("left monitor must be left of right monitor")\n\t}\n\n\tboundary := float64(right.X)\n\tif mode == CoordinateNative {\n\t\tleftRect := Rect{X: float64(left.X), Y: float64(left.Y), W: float64(left.Width), H: float64(left.Height)}\n\t\trightRect := Rect{X: float64(right.X), Y: float64(right.Y), W: float64(right.Width), H: float64(right.Height)}\n\t\tadjacencyError := math.Abs(leftRect.X + leftRect.W - boundary)\n\t\tif adjacencyError > 4 {\n\t\t\treturn PairGeometry{}, fmt.Errorf("monitors are not horizontally adjacent; boundary error %.2f", adjacencyError)\n\t\t}\n\t\treturn PairGeometry{\n\t\t\tBoundaryX:           boundary,\n\t\t\tLeftRect:            leftRect,\n\t\t\tRightRect:           rightRect,\n\t\t\tEffectiveLeftScale:  1,\n\t\t\tEffectiveRightScale: 1,\n\t\t}, nil\n\t}\n\n\tleftLogicalWidth := float64(right.X - left.X)\n\tif leftLogicalWidth <= 0 || left.Width <= 0 || right.Width <= 0 {\n\t\treturn PairGeometry{}, errors.New("invalid logical monitor width")\n\t}\n\n\tleftScale := float64(left.Width) / leftLogicalWidth\n\tif leftScale <= 0 || math.IsInf(leftScale, 0) || math.IsNaN(leftScale) {\n\t\treturn PairGeometry{}, errors.New("invalid inferred left monitor scale")\n\t}\n\t// A large discrepancy means the monitors probably are not actually adjacent;\n\t// do not use the inferred span to paper over an incompatible layout.\n\tif left.Scale > 0 && math.Abs(leftScale-left.Scale) > 0.05 {\n\t\treturn PairGeometry{}, fmt.Errorf(\n\t\t\t"monitors are not horizontally adjacent; inferred scale %.5f differs from reported scale %.5f",\n\t\t\tleftScale,\n\t\t\tleft.Scale,\n\t\t)\n\t}\n\n\trightScale := right.Scale\n\tif rightScale <= 0 {\n\t\treturn PairGeometry{}, errors.New("invalid right monitor scale")\n\t}\n\tif math.Abs(left.Scale-right.Scale) <= 0.02 {\n\t\trightScale = leftScale\n\t}\n\n\tleftRect := Rect{\n\t\tX: float64(left.X),\n\t\tY: float64(left.Y),\n\t\tW: leftLogicalWidth,\n\t\tH: float64(left.Height) / leftScale,\n\t}\n\trightRect := Rect{\n\t\tX: float64(right.X),\n\t\tY: float64(right.Y),\n\t\tW: float64(right.Width) / rightScale,\n\t\tH: float64(right.Height) / rightScale,\n\t}\n\n\treturn PairGeometry{\n\t\tBoundaryX:           boundary,\n\t\tLeftRect:            leftRect,\n\t\tRightRect:           rightRect,\n\t\tEffectiveLeftScale:  leftScale,\n\t\tEffectiveRightScale: rightScale,\n\t}, nil\n}',
    'rectFor': 'func (v Validation) rectFor(m Monitor) Rect {\n\tif m.Name == v.Left.Name {\n\t\treturn v.Geometry.LeftRect\n\t}\n\tif m.Name == v.Right.Name {\n\t\treturn v.Geometry.RightRect\n\t}\n\treturn Rect{}\n}',
    'physicalDistanceFromBottomInRect': 'func physicalDistanceFromBottomInRect(m Monitor, rect Rect, y float64) (float64, error) {\n\tif m.PhysicalHeight <= 0 {\n\t\treturn 0, errors.New("physical height must be positive")\n\t}\n\tif rect.H <= 0 {\n\t\treturn 0, errors.New("coordinate height must be positive")\n\t}\n\tbottom := rect.Y + rect.H\n\tdistanceUnits := bottom - y\n\treturn distanceUnits * float64(m.PhysicalHeight) / rect.H, nil\n}',
    'mapPhysicalHeightInRects': 'func mapPhysicalHeightInRects(source, destination Monitor, sourceRect, destinationRect Rect, sourceY float64) (float64, bool, error) {\n\tdistanceMM, err := physicalDistanceFromBottomInRect(source, sourceRect, sourceY)\n\tif err != nil {\n\t\treturn 0, false, err\n\t}\n\tsharedHeight := math.Min(float64(source.PhysicalHeight), float64(destination.PhysicalHeight))\n\tconst epsilon = 0.5\n\tif distanceMM < -epsilon || distanceMM > sharedHeight+epsilon {\n\t\treturn 0, false, nil\n\t}\n\n\tif destinationRect.H <= 0 || destination.PhysicalHeight <= 0 {\n\t\treturn 0, false, errors.New("destination geometry is invalid")\n\t}\n\tdestinationDistance := distanceMM * destinationRect.H / float64(destination.PhysicalHeight)\n\tdestinationBottom := destinationRect.Y + destinationRect.H\n\ty := destinationBottom - destinationDistance\n\treturn clamp(y, destinationRect.Y+1, destinationBottom-1), true, nil\n}',
    'mapPhysicalHeight': 'func mapPhysicalHeight(source, destination Monitor, mode CoordinateMode, sourceY float64) (float64, bool, error) {\n\tsourceW, sourceH := coordDimensions(source, mode)\n\tdestinationW, destinationH := coordDimensions(destination, mode)\n\treturn mapPhysicalHeightInRects(\n\t\tsource,\n\t\tdestination,\n\t\tRect{X: float64(source.X), Y: float64(source.Y), W: sourceW, H: sourceH},\n\t\tRect{X: float64(destination.X), Y: float64(destination.Y), W: destinationW, H: destinationH},\n\t\tsourceY,\n\t)\n}',
    'processCursor': 'func (d *Daemon) processCursor(ctx context.Context) {\n\td.mu.RLock()\n\tif d.validation == nil || d.state.State != "active" {\n\t\td.mu.RUnlock()\n\t\treturn\n\t}\n\tvalidation := *d.validation\n\tprevious := d.previous\n\tlastWarp := d.lastWarp\n\td.mu.RUnlock()\n\n\tpoint, err := d.client.Cursor(ctx)\n\tif err != nil {\n\t\td.mu.Lock()\n\t\td.cursorFails++\n\t\tfailures := d.cursorFails\n\t\td.mu.Unlock()\n\t\tif failures >= 3 {\n\t\t\td.Disable("cursor sampling failed repeatedly: "+err.Error(), true)\n\t\t}\n\t\treturn\n\t}\n\n\tnow := time.Now()\n\tcurrentMonitor := monitorAt(point, validation)\n\tcurrent := &cursorSample{Point: point, Monitor: currentMonitor, At: now}\n\n\tif now.Sub(lastWarp.At) < 90*time.Millisecond && distance(point, lastWarp.Point) <= 6 {\n\t\td.setPrevious(current)\n\t\treturn\n\t}\n\tif previous == nil {\n\t\td.setPrevious(current)\n\t\treturn\n\t}\n\tif previous.Monitor != "" && previous.Monitor == currentMonitor {\n\t\tif d.handleEdgeAttempt(ctx, previous, current, validation) {\n\t\t\treturn\n\t\t}\n\t\td.setPrevious(current)\n\t\treturn\n\t}\n\tif previous.Monitor == "" || currentMonitor == "" {\n\t\td.setPrevious(current)\n\t\treturn\n\t}\n\n\tvar source, destination Monitor\n\tvar sourceName, destinationName string\n\tvar leftToRight bool\n\tswitch {\n\tcase previous.Monitor == "left" && currentMonitor == "right":\n\t\tsource, destination = validation.Left, validation.Right\n\t\tsourceName, destinationName = validation.Left.Name, validation.Right.Name\n\t\tleftToRight = true\n\tcase previous.Monitor == "right" && currentMonitor == "left":\n\t\tsource, destination = validation.Right, validation.Left\n\t\tsourceName, destinationName = validation.Right.Name, validation.Left.Name\n\t\tleftToRight = false\n\tdefault:\n\t\td.setPrevious(current)\n\t\treturn\n\t}\n\n\tboundaryX := validation.Geometry.BoundaryX\n\tcrossingY := interpolateYAtX(previous.Point, point, boundaryX)\n\tmappedY, valid, mapErr := mapPhysicalHeightInRects(source, destination, validation.rectFor(source), validation.rectFor(destination), crossingY)\n\tif mapErr != nil {\n\t\td.Disable("geometry mapping failed: "+mapErr.Error(), true)\n\t\treturn\n\t}\n\n\tif !valid {\n\t\tsourceRect := validation.rectFor(source)\n\t\ttargetX := sourceRect.X + sourceRect.W - 3\n\t\tif !leftToRight {\n\t\t\ttargetX = sourceRect.X + 2\n\t\t}\n\t\ttargetY := clamp(crossingY, sourceRect.Y+1, sourceRect.Y+sourceRect.H-1)\n\t\tif err := d.warp(ctx, Cursor{X: targetX, Y: targetY}, sourceName, sourceName, true); err != nil {\n\t\t\td.handleWarpFailure(err)\n\t\t\treturn\n\t\t}\n\t\td.logger.Debug("dead-zone crossing blocked", "monitor", sourceName, "y", crossingY)\n\t\treturn\n\t}\n\n\tdestinationRect := validation.rectFor(destination)\n\ttargetX := destinationRect.X + 2\n\tif !leftToRight {\n\t\ttargetX = destinationRect.X + destinationRect.W - 3\n\t}\n\tif err := d.warp(ctx, Cursor{X: targetX, Y: mappedY}, sourceName, destinationName, false); err != nil {\n\t\td.handleWarpFailure(err)\n\t\treturn\n\t}\n}',
    'handleEdgeAttempt': 'func (d *Daemon) handleEdgeAttempt(ctx context.Context, previous, current *cursorSample, validation Validation) bool {\n\tconst edgeThreshold = 2.5\n\tconst movementThreshold = 0.01\n\n\tvar source, destination Monitor\n\tvar sourceName, destinationName string\n\tvar leftToRight bool\n\n\tswitch current.Monitor {\n\tcase "left":\n\t\tsource, destination = validation.Left, validation.Right\n\t\tsourceName, destinationName = validation.Left.Name, validation.Right.Name\n\t\tleftToRight = true\n\tcase "right":\n\t\tsource, destination = validation.Right, validation.Left\n\t\tsourceName, destinationName = validation.Right.Name, validation.Left.Name\n\t\tleftToRight = false\n\tdefault:\n\t\treturn false\n\t}\n\n\tsourceRect := validation.rectFor(source)\n\tattempting := false\n\tif leftToRight {\n\t\tedge := sourceRect.X + sourceRect.W\n\t\tattempting = current.Point.X >= edge-edgeThreshold && current.Point.X > previous.Point.X+movementThreshold\n\t} else {\n\t\tedge := sourceRect.X\n\t\tattempting = current.Point.X <= edge+edgeThreshold && current.Point.X < previous.Point.X-movementThreshold\n\t}\n\tif !attempting {\n\t\treturn false\n\t}\n\n\tmappedY, valid, err := mapPhysicalHeightInRects(source, destination, validation.rectFor(source), validation.rectFor(destination), current.Point.Y)\n\tif err != nil {\n\t\td.Disable("geometry mapping failed: "+err.Error(), true)\n\t\treturn true\n\t}\n\tif !valid {\n\t\ttargetX := sourceRect.X + sourceRect.W - 3\n\t\tif !leftToRight {\n\t\t\ttargetX = sourceRect.X + 2\n\t\t}\n\t\ttargetY := clamp(current.Point.Y, sourceRect.Y+1, sourceRect.Y+sourceRect.H-1)\n\t\tif err := d.warp(ctx, Cursor{X: targetX, Y: targetY}, sourceName, sourceName, true); err != nil {\n\t\t\td.handleWarpFailure(err)\n\t\t}\n\t\td.logger.Debug("dead-zone edge attempt blocked", "monitor", sourceName, "y", current.Point.Y)\n\t\treturn true\n\t}\n\n\tdestinationRect := validation.rectFor(destination)\n\ttargetX := destinationRect.X + 2\n\tif !leftToRight {\n\t\ttargetX = destinationRect.X + destinationRect.W - 3\n\t}\n\tif err := d.warp(ctx, Cursor{X: targetX, Y: mappedY}, sourceName, destinationName, false); err != nil {\n\t\td.handleWarpFailure(err)\n\t}\n\treturn true\n}',
    'monitorAt': 'func monitorAt(point Cursor, validation Validation) string {\n\t// Resolve the shared seam explicitly so a rounded scale can never create an\n\t// artificial overlap where both rectangles claim the same point.\n\tif point.X < validation.Geometry.BoundaryX {\n\t\tif validation.Geometry.LeftRect.Contains(point) {\n\t\t\treturn "left"\n\t\t}\n\t\treturn ""\n\t}\n\tif validation.Geometry.RightRect.Contains(point) {\n\t\treturn "right"\n\t}\n\treturn ""\n}',
    'runValidate': 'func runValidate(ctx context.Context, store *Store, args []string) error {\n\tif len(args) != 1 {\n\t\treturn errors.New("usage: desk-cursor validate <profile>")\n\t}\n\tcfg, err := store.Load()\n\tif err != nil {\n\t\treturn err\n\t}\n\tprofile, ok := cfg.Profiles[args[0]]\n\tif !ok {\n\t\treturn fmt.Errorf("profile %q does not exist", args[0])\n\t}\n\tmonitors, err := (HyprClient{}).Monitors(ctx)\n\tif err != nil {\n\t\treturn err\n\t}\n\tvalidation, err := validateProfile(profile, monitors)\n\tif err != nil {\n\t\treturn err\n\t}\n\treturn printJSON(map[string]any{\n\t\t"valid":                 true,\n\t\t"left_connector":        validation.Left.Name,\n\t\t"right_connector":       validation.Right.Name,\n\t\t"coordinate_mode":       validation.Mode,\n\t\t"boundary_x":            validation.Geometry.BoundaryX,\n\t\t"effective_left_scale":  validation.Geometry.EffectiveLeftScale,\n\t\t"effective_right_scale": validation.Geometry.EffectiveRightScale,\n\t})\n}',
    'runDebug': 'func runDebug(ctx context.Context, args []string) error {\n\tif len(args) != 1 {\n\t\treturn errors.New("usage: desk-cursor debug <monitors|cursor>")\n\t}\n\tclient := HyprClient{}\n\tswitch args[0] {\n\tcase "monitors":\n\t\tmonitors, err := client.Monitors(ctx)\n\t\tif err != nil {\n\t\t\treturn err\n\t\t}\n\t\tactive := activeMonitors(monitors)\n\t\tresult := map[string]any{"monitors": monitors}\n\t\tif len(active) == 2 {\n\t\t\tleft, right, err := chooseLeftRight(active, "", "")\n\t\t\tif err == nil {\n\t\t\t\tmode := inferCoordinateMode(left, right)\n\t\t\t\tresult["inferred_coordinate_mode"] = mode\n\t\t\t\tgeometry, geometryErr := pairGeometry(left, right, mode)\n\t\t\t\tif geometryErr != nil {\n\t\t\t\t\tresult["geometry_error"] = geometryErr.Error()\n\t\t\t\t} else {\n\t\t\t\t\tresult["boundary_x"] = geometry.BoundaryX\n\t\t\t\t\tresult["effective_left_scale"] = geometry.EffectiveLeftScale\n\t\t\t\t\tresult["effective_right_scale"] = geometry.EffectiveRightScale\n\t\t\t\t\tresult["left_rect"] = geometry.LeftRect\n\t\t\t\t\tresult["right_rect"] = geometry.RightRect\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t\treturn printJSON(result)\n\tcase "cursor":\n\t\tcursor, err := client.Cursor(ctx)\n\t\tif err != nil {\n\t\t\treturn err\n\t\t}\n\t\treturn printJSON(cursor)\n\tdefault:\n\t\treturn fmt.Errorf("unknown debug command %q", args[0])\n\t}\n}',
    'runSelfTest': 'func runSelfTest() error {\n\tleft := Monitor{\n\t\tName: "HDMI-A-1", Width: 2560, Height: 1440,\n\t\tPhysicalWidth: 530, PhysicalHeight: 300,\n\t\tX: -2560, Y: 0, Scale: 1.33,\n\t}\n\tright := Monitor{\n\t\tName: "eDP-1", Width: 2560, Height: 1600,\n\t\tPhysicalWidth: 340, PhysicalHeight: 220,\n\t\tX: 0, Y: 0, Scale: 1.33,\n\t}\n\tmode := inferCoordinateMode(left, right)\n\tif mode != CoordinateNative {\n\t\treturn fmt.Errorf("coordinate mode: got %s, want native", mode)\n\t}\n\n\ttests := []struct {\n\t\tname        string\n\t\tsource      Monitor\n\t\tdestination Monitor\n\t\tsourceY     float64\n\t\twantValid   bool\n\t\twantY       float64\n\t\ttolerance   float64\n\t}{\n\t\t{name: "bottom left to right", source: left, destination: right, sourceY: 1440, wantValid: true, wantY: 1599, tolerance: 1.1},\n\t\t{name: "150mm left to right", source: left, destination: right, sourceY: 720, wantValid: true, wantY: 509.09, tolerance: 0.1},\n\t\t{name: "left upper dead zone", source: left, destination: right, sourceY: 240, wantValid: false},\n\t\t{name: "110mm right to left", source: right, destination: left, sourceY: 800, wantValid: true, wantY: 912, tolerance: 0.1},\n\t}\n\n\tfor _, test := range tests {\n\t\tgotY, valid, err := mapPhysicalHeight(test.source, test.destination, mode, test.sourceY)\n\t\tif err != nil {\n\t\t\treturn fmt.Errorf("%s: %w", test.name, err)\n\t\t}\n\t\tif valid != test.wantValid {\n\t\t\treturn fmt.Errorf("%s: valid=%v, want %v", test.name, valid, test.wantValid)\n\t\t}\n\t\tif valid && math.Abs(gotY-test.wantY) > test.tolerance {\n\t\t\treturn fmt.Errorf("%s: y=%.3f, want %.3f", test.name, gotY, test.wantY)\n\t\t}\n\t}\n\n\tlogicalLeft := left\n\tlogicalLeft.X = -1920\n\tlogicalRight := right\n\tlogicalRight.X = 0\n\tlogicalMode := inferCoordinateMode(logicalLeft, logicalRight)\n\tif logicalMode != CoordinateLogical {\n\t\treturn fmt.Errorf("rounded-scale coordinate mode: got %s, want logical", logicalMode)\n\t}\n\tgeometry, err := pairGeometry(logicalLeft, logicalRight, logicalMode)\n\tif err != nil {\n\t\treturn fmt.Errorf("rounded-scale pair geometry: %w", err)\n\t}\n\tif math.Abs(geometry.BoundaryX) > 0.001 || math.Abs(geometry.LeftRect.W-1920) > 0.001 || math.Abs(geometry.RightRect.W-1920) > 0.001 {\n\t\treturn fmt.Errorf("rounded-scale geometry mismatch: boundary=%.3f leftW=%.3f rightW=%.3f", geometry.BoundaryX, geometry.LeftRect.W, geometry.RightRect.W)\n\t}\n\tif math.Abs(geometry.LeftRect.H-1080) > 0.001 || math.Abs(geometry.RightRect.H-1200) > 0.001 {\n\t\treturn fmt.Errorf("rounded-scale heights mismatch: leftH=%.3f rightH=%.3f", geometry.LeftRect.H, geometry.RightRect.H)\n\t}\n\tif monitorAt(Cursor{X: -0.1, Y: 500}, Validation{Left: logicalLeft, Right: logicalRight, Mode: logicalMode, Geometry: geometry}) != "left" {\n\t\treturn errors.New("point left of seam was not assigned to left monitor")\n\t}\n\tif monitorAt(Cursor{X: 0, Y: 500}, Validation{Left: logicalLeft, Right: logicalRight, Mode: logicalMode, Geometry: geometry}) != "right" {\n\t\treturn errors.New("point on seam was not assigned to right monitor")\n\t}\n\n\tfmt.Println("self-test: PASS")\n\treturn nil\n}',
}


replace_declaration(r"^type Validation struct\s*\{", BLOCKS["Validation"])
replace_declaration(r"^func validateProfile\s*\(", BLOCKS["validateProfile"])
replace_declaration(r"^func mapPhysicalHeight\s*\(", BLOCKS["mapPhysicalHeight"])
replace_declaration(r"^func \(d \*Daemon\) processCursor\s*\(", BLOCKS["processCursor"])
replace_declaration(r"^func \(d \*Daemon\) handleEdgeAttempt\s*\(", BLOCKS["handleEdgeAttempt"])
replace_declaration(r"^func monitorAt\s*\(", BLOCKS["monitorAt"])
replace_declaration(r"^func runValidate\s*\(", BLOCKS["runValidate"])
replace_declaration(r"^func runDebug\s*\(", BLOCKS["runDebug"])
replace_declaration(r"^func runSelfTest\s*\(", BLOCKS["runSelfTest"])

for pattern in (
    r"^type PairGeometry struct\s*\{",
    r"^func pairGeometry\s*\(",
    r"^func \(v Validation\) rectFor\s*\(",
    r"^func physicalDistanceFromBottomInRect\s*\(",
    r"^func mapPhysicalHeightInRects\s*\(",
):
    remove_declaration(pattern)

validation_start = re.search(r"^type Validation struct\s*\{", text, re.MULTILINE)
if validation_start is None:
    raise RuntimeError("Validation type disappeared during patch")
text = text[:validation_start.start()] + BLOCKS["PairGeometry"].rstrip() + "\n\n" + text[validation_start.start():]

mapping_start = re.search(r"^func mapPhysicalHeight\s*\(", text, re.MULTILINE)
if mapping_start is None:
    raise RuntimeError("mapPhysicalHeight disappeared during patch")
helper_block = "\n\n".join([
    BLOCKS["pairGeometry"].rstrip(),
    BLOCKS["rectFor"].rstrip(),
    BLOCKS["physicalDistanceFromBottomInRect"].rstrip(),
    BLOCKS["mapPhysicalHeightInRects"].rstrip(),
])
text = text[:mapping_start.start()] + helper_block + "\n\n" + text[mapping_start.start():]

path.write_text(text)
PYCODE

gofmt -w -- "$src"
go vet "$src"

tmpbin=$(mktemp "${TMPDIR:-/tmp}/desk-cursor.XXXXXX")
rm -f -- "$tmpbin"
trap 'rm -f -- "$tmpbin"' EXIT

go build -trimpath -o "$tmpbin" "$src"
"$tmpbin" self-test

print -- "Patch applied successfully: $src"
print -- "Rebuild/install with:"
print -- "  go build -trimpath -ldflags='-s -w' -o ~/.local/bin/desk-cursor ${(q)src}"