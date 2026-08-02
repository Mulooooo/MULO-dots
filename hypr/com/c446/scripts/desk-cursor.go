package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	appName       = "desk-cursor"
	configVersion = 1
	defaultPollHz = 120
	maxPollHz     = 240
)

type Monitor struct {
	ID             int     `json:"id"`
	Name           string  `json:"name"`
	Description    string  `json:"description"`
	Make           string  `json:"make"`
	Model          string  `json:"model"`
	Serial         string  `json:"serial"`
	Width          int     `json:"width"`
	Height         int     `json:"height"`
	PhysicalWidth  int     `json:"physicalWidth"`
	PhysicalHeight int     `json:"physicalHeight"`
	RefreshRate    float64 `json:"refreshRate"`
	X              int     `json:"x"`
	Y              int     `json:"y"`
	Scale          float64 `json:"scale"`
	Transform      int     `json:"transform"`
	Disabled       bool    `json:"disabled"`
	MirrorOf       string  `json:"mirrorOf"`
	DPMSStatus     bool    `json:"dpmsStatus"`
}

type Cursor struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type CoordinateMode string

const (
	CoordinateNative  CoordinateMode = "native"
	CoordinateLogical CoordinateMode = "logical"
)

type MonitorSpec struct {
	ConnectorHint    string  `json:"connector_hint"`
	Make             string  `json:"make"`
	Model            string  `json:"model"`
	Serial           string  `json:"serial"`
	Description      string  `json:"description"`
	PhysicalWidthMM  int     `json:"physical_width_mm"`
	PhysicalHeightMM int     `json:"physical_height_mm"`
	PixelWidth       int     `json:"pixel_width"`
	PixelHeight      int     `json:"pixel_height"`
	Scale            float64 `json:"scale"`
	Transform        int     `json:"transform"`
	RefreshRate      float64 `json:"refresh_rate"`
}

type Profile struct {
	Alignment      string         `json:"alignment"`
	CoordinateMode CoordinateMode `json:"coordinate_mode"`
	Left           MonitorSpec    `json:"left"`
	Right          MonitorSpec    `json:"right"`
	RelativeX      int            `json:"relative_x"`
	RelativeY      int            `json:"relative_y"`
	CapturedAt     time.Time      `json:"captured_at"`
}

type Config struct {
	Version  int                `json:"version"`
	Profiles map[string]Profile `json:"profiles"`
}

type RuntimeState struct {
	DaemonRunning      bool      `json:"daemon_running"`
	State              string    `json:"state"`
	Profile            string    `json:"profile,omitempty"`
	Valid              bool      `json:"valid"`
	Reason             string    `json:"reason,omitempty"`
	PollHz             int       `json:"poll_hz"`
	DryRun             bool      `json:"dry_run"`
	LastValidationTime time.Time `json:"last_validation_time,omitempty"`
	LastRemapTime      time.Time `json:"last_remap_time,omitempty"`
	LastSource         string    `json:"last_source,omitempty"`
	LastDestination    string    `json:"last_destination,omitempty"`
	RemapCount         uint64    `json:"remap_count"`
}

type ControlRequest struct {
	Command string `json:"command"`
	Profile string `json:"profile,omitempty"`
}

type ControlResponse struct {
	OK      bool         `json:"ok"`
	Message string       `json:"message,omitempty"`
	Status  RuntimeState `json:"status"`
}

type Paths struct {
	ConfigDir    string
	ProfilesFile string
	RuntimeDir   string
	ControlSock  string
	StateFile    string
}

func resolvePaths() (Paths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return Paths{}, fmt.Errorf("resolve home directory: %w", err)
	}

	configHome := strings.TrimSpace(os.Getenv("XDG_CONFIG_HOME"))
	if configHome == "" {
		configHome = filepath.Join(home, ".config")
	}

	runtimeHome := strings.TrimSpace(os.Getenv("XDG_RUNTIME_DIR"))
	if runtimeHome == "" {
		runtimeHome = filepath.Join(os.TempDir(), fmt.Sprintf("%s-%d", appName, os.Getuid()))
	}

	configDir := filepath.Join(configHome, appName)
	runtimeDir := filepath.Join(runtimeHome, appName)
	return Paths{
		ConfigDir:    configDir,
		ProfilesFile: filepath.Join(configDir, "profiles.json"),
		RuntimeDir:   runtimeDir,
		ControlSock:  filepath.Join(runtimeDir, "control.sock"),
		StateFile:    filepath.Join(runtimeDir, "state.json"),
	}, nil
}

type Store struct {
	paths Paths
}

func NewStore(paths Paths) *Store {
	return &Store{paths: paths}
}

func (s *Store) Load() (Config, error) {
	data, err := os.ReadFile(s.paths.ProfilesFile)
	if errors.Is(err, os.ErrNotExist) {
		return Config{Version: configVersion, Profiles: map[string]Profile{}}, nil
	}
	if err != nil {
		return Config{}, fmt.Errorf("read profiles: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("decode profiles: %w", err)
	}
	if cfg.Version != configVersion {
		return Config{}, fmt.Errorf("unsupported profiles version %d", cfg.Version)
	}
	if cfg.Profiles == nil {
		cfg.Profiles = map[string]Profile{}
	}
	return cfg, nil
}

func (s *Store) Save(cfg Config) error {
	if err := os.MkdirAll(s.paths.ConfigDir, 0o700); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	cfg.Version = configVersion
	if cfg.Profiles == nil {
		cfg.Profiles = map[string]Profile{}
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("encode profiles: %w", err)
	}
	data = append(data, '\n')

	tmp, err := os.CreateTemp(s.paths.ConfigDir, ".profiles-*.json")
	if err != nil {
		return fmt.Errorf("create temporary profiles file: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return fmt.Errorf("chmod temporary profiles file: %w", err)
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return fmt.Errorf("write temporary profiles file: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return fmt.Errorf("sync temporary profiles file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close temporary profiles file: %w", err)
	}
	if err := os.Rename(tmpName, s.paths.ProfilesFile); err != nil {
		return fmt.Errorf("replace profiles file: %w", err)
	}
	return nil
}

type HyprClient struct{}

func (HyprClient) Monitors(ctx context.Context) ([]Monitor, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "hyprctl", "-j", "monitors", "all").CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("hyprctl monitors: %w: %s", err, strings.TrimSpace(string(out)))
	}
	var monitors []Monitor
	if err := json.Unmarshal(out, &monitors); err != nil {
		return nil, fmt.Errorf("decode monitor JSON: %w", err)
	}
	return monitors, nil
}

func (HyprClient) Cursor(ctx context.Context) (Cursor, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "hyprctl", "-j", "cursorpos").CombinedOutput()
	if err != nil {
		return Cursor{}, fmt.Errorf("hyprctl cursorpos: %w: %s", err, strings.TrimSpace(string(out)))
	}
	var cursor Cursor
	if err := json.Unmarshal(out, &cursor); err != nil {
		return Cursor{}, fmt.Errorf("decode cursor JSON: %w", err)
	}
	return cursor, nil
}

func (HyprClient) Warp(ctx context.Context, x, y float64) error {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()

	xs := strconv.Itoa(int(math.Round(x)))
	ys := strconv.Itoa(int(math.Round(y)))
	out, err := exec.CommandContext(ctx, "hyprctl", "dispatch", "movecursor", xs, ys).CombinedOutput()
	if err != nil {
		return fmt.Errorf("hyprctl movecursor: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func activeMonitors(monitors []Monitor) []Monitor {
	active := make([]Monitor, 0, len(monitors))
	for _, monitor := range monitors {
		if !monitor.Disabled && monitor.DPMSStatus {
			active = append(active, monitor)
		}
	}
	return active
}

func mirrorEnabled(m Monitor) bool {
	value := strings.TrimSpace(strings.ToLower(m.MirrorOf))
	return value != "" && value != "none"
}

func coordDimensions(m Monitor, mode CoordinateMode) (float64, float64) {
	if mode == CoordinateLogical {
		return float64(m.Width) / m.Scale, float64(m.Height) / m.Scale
	}
	return float64(m.Width), float64(m.Height)
}

func inferCoordinateMode(left, right Monitor) CoordinateMode {
	nativeError := math.Abs(float64(left.X+left.Width) - float64(right.X))
	logicalWidth := float64(left.Width)
	if left.Scale > 0 {
		logicalWidth /= left.Scale
	}
	logicalError := math.Abs(float64(left.X) + logicalWidth - float64(right.X))
	if logicalError+0.5 < nativeError {
		return CoordinateLogical
	}
	return CoordinateNative
}

func captureSpec(m Monitor) MonitorSpec {
	return MonitorSpec{
		ConnectorHint:    m.Name,
		Make:             m.Make,
		Model:            m.Model,
		Serial:           m.Serial,
		Description:      m.Description,
		PhysicalWidthMM:  m.PhysicalWidth,
		PhysicalHeightMM: m.PhysicalHeight,
		PixelWidth:       m.Width,
		PixelHeight:      m.Height,
		Scale:            m.Scale,
		Transform:        m.Transform,
		RefreshRate:      m.RefreshRate,
	}
}

func monitorIdentityMatches(spec MonitorSpec, live Monitor) bool {
	if spec.Serial != "" {
		return live.Serial == spec.Serial
	}
	if spec.Make != "" && spec.Model != "" {
		return live.Make == spec.Make &&
			live.Model == spec.Model &&
			live.PhysicalWidth == spec.PhysicalWidthMM &&
			live.PhysicalHeight == spec.PhysicalHeightMM
	}
	return live.Description == spec.Description &&
		live.PhysicalWidth == spec.PhysicalWidthMM &&
		live.PhysicalHeight == spec.PhysicalHeightMM
}

type PairGeometry struct {
	BoundaryX           float64
	LeftRect            Rect
	RightRect           Rect
	EffectiveLeftScale  float64
	EffectiveRightScale float64
}

type Validation struct {
	Left     Monitor
	Right    Monitor
	Mode     CoordinateMode
	Geometry PairGeometry
}

func validateProfile(profile Profile, monitors []Monitor) (Validation, error) {
	active := activeMonitors(monitors)
	if len(active) != 2 {
		return Validation{}, fmt.Errorf("expected exactly 2 active monitors, found %d", len(active))
	}

	for _, monitor := range active {
		if mirrorEnabled(monitor) {
			return Validation{}, fmt.Errorf("monitor %s mirrors %s", monitor.Name, monitor.MirrorOf)
		}
		if monitor.Transform != 0 {
			return Validation{}, fmt.Errorf("monitor %s has unsupported transform %d", monitor.Name, monitor.Transform)
		}
		if monitor.PhysicalWidth <= 0 || monitor.PhysicalHeight <= 0 {
			return Validation{}, fmt.Errorf("monitor %s has invalid physical dimensions", monitor.Name)
		}
		if monitor.Scale <= 0 {
			return Validation{}, fmt.Errorf("monitor %s has invalid scale %.3f", monitor.Name, monitor.Scale)
		}
	}

	var left, right *Monitor
	for i := range active {
		monitor := &active[i]
		if monitorIdentityMatches(profile.Left, *monitor) {
			left = monitor
		}
		if monitorIdentityMatches(profile.Right, *monitor) {
			right = monitor
		}
	}
	if left == nil {
		return Validation{}, errors.New("saved left monitor identity is not present")
	}
	if right == nil {
		return Validation{}, errors.New("saved right monitor identity is not present")
	}
	if left.Name == right.Name {
		return Validation{}, errors.New("left and right profile identities resolved to the same monitor")
	}

	if err := validateMonitorMode(profile.Left, *left); err != nil {
		return Validation{}, fmt.Errorf("left monitor: %w", err)
	}
	if err := validateMonitorMode(profile.Right, *right); err != nil {
		return Validation{}, fmt.Errorf("right monitor: %w", err)
	}
	if left.X >= right.X {
		return Validation{}, fmt.Errorf("saved left monitor %s is not left of %s", left.Name, right.Name)
	}

	mode := inferCoordinateMode(*left, *right)
	if profile.CoordinateMode != "" && mode != profile.CoordinateMode {
		return Validation{}, fmt.Errorf("coordinate mode changed from %s to %s", profile.CoordinateMode, mode)
	}
	if absInt((right.X-left.X)-profile.RelativeX) > 3 || absInt((right.Y-left.Y)-profile.RelativeY) > 3 {
		return Validation{}, fmt.Errorf(
			"relative layout changed: got (%d,%d), expected (%d,%d)",
			right.X-left.X,
			right.Y-left.Y,
			profile.RelativeX,
			profile.RelativeY,
		)
	}

	geometry, err := pairGeometry(*left, *right, mode)
	if err != nil {
		return Validation{}, err
	}
	if overlapLength(
		geometry.LeftRect.Y,
		geometry.LeftRect.Y+geometry.LeftRect.H,
		geometry.RightRect.Y,
		geometry.RightRect.Y+geometry.RightRect.H,
	) <= 0 {
		return Validation{}, errors.New("monitor rectangles do not overlap vertically")
	}

	return Validation{Left: *left, Right: *right, Mode: mode, Geometry: geometry}, nil
}

func validateMonitorMode(spec MonitorSpec, live Monitor) error {
	if live.Width != spec.PixelWidth || live.Height != spec.PixelHeight {
		return fmt.Errorf("resolution changed from %dx%d to %dx%d", spec.PixelWidth, spec.PixelHeight, live.Width, live.Height)
	}
	if math.Abs(live.Scale-spec.Scale) > 0.01 {
		return fmt.Errorf("scale changed from %.3f to %.3f", spec.Scale, live.Scale)
	}
	if live.Transform != spec.Transform {
		return fmt.Errorf("transform changed from %d to %d", spec.Transform, live.Transform)
	}
	return nil
}

func overlapLength(a1, a2, b1, b2 float64) float64 {
	return math.Max(0, math.Min(a2, b2)-math.Max(a1, b1))
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

type Rect struct {
	X float64
	Y float64
	W float64
	H float64
}

func monitorRect(m Monitor, mode CoordinateMode) Rect {
	w, h := coordDimensions(m, mode)
	return Rect{X: float64(m.X), Y: float64(m.Y), W: w, H: h}
}

func (r Rect) Contains(point Cursor) bool {
	return point.X >= r.X && point.X < r.X+r.W && point.Y >= r.Y && point.Y < r.Y+r.H
}

func physicalDistanceFromBottom(m Monitor, mode CoordinateMode, y float64) (float64, error) {
	if m.PhysicalHeight <= 0 {
		return 0, errors.New("physical height must be positive")
	}
	_, h := coordDimensions(m, mode)
	if h <= 0 {
		return 0, errors.New("coordinate height must be positive")
	}
	bottom := float64(m.Y) + h
	distanceUnits := bottom - y
	return distanceUnits * float64(m.PhysicalHeight) / h, nil
}

func pairGeometry(left, right Monitor, mode CoordinateMode) (PairGeometry, error) {
	if left.X >= right.X {
		return PairGeometry{}, errors.New("left monitor must be left of right monitor")
	}

	boundary := float64(right.X)
	if mode == CoordinateNative {
		leftRect := Rect{X: float64(left.X), Y: float64(left.Y), W: float64(left.Width), H: float64(left.Height)}
		rightRect := Rect{X: float64(right.X), Y: float64(right.Y), W: float64(right.Width), H: float64(right.Height)}
		adjacencyError := math.Abs(leftRect.X + leftRect.W - boundary)
		if adjacencyError > 4 {
			return PairGeometry{}, fmt.Errorf("monitors are not horizontally adjacent; boundary error %.2f", adjacencyError)
		}
		return PairGeometry{
			BoundaryX:           boundary,
			LeftRect:            leftRect,
			RightRect:           rightRect,
			EffectiveLeftScale:  1,
			EffectiveRightScale: 1,
		}, nil
	}

	leftLogicalWidth := float64(right.X - left.X)
	if leftLogicalWidth <= 0 || left.Width <= 0 || right.Width <= 0 {
		return PairGeometry{}, errors.New("invalid logical monitor width")
	}

	leftScale := float64(left.Width) / leftLogicalWidth
	if leftScale <= 0 || math.IsInf(leftScale, 0) || math.IsNaN(leftScale) {
		return PairGeometry{}, errors.New("invalid inferred left monitor scale")
	}
	// A large discrepancy means the monitors probably are not actually adjacent;
	// do not use the inferred span to paper over an incompatible layout.
	if left.Scale > 0 && math.Abs(leftScale-left.Scale) > 0.05 {
		return PairGeometry{}, fmt.Errorf(
			"monitors are not horizontally adjacent; inferred scale %.5f differs from reported scale %.5f",
			leftScale,
			left.Scale,
		)
	}

	rightScale := right.Scale
	if rightScale <= 0 {
		return PairGeometry{}, errors.New("invalid right monitor scale")
	}
	if math.Abs(left.Scale-right.Scale) <= 0.02 {
		rightScale = leftScale
	}

	leftRect := Rect{
		X: float64(left.X),
		Y: float64(left.Y),
		W: leftLogicalWidth,
		H: float64(left.Height) / leftScale,
	}
	rightRect := Rect{
		X: float64(right.X),
		Y: float64(right.Y),
		W: float64(right.Width) / rightScale,
		H: float64(right.Height) / rightScale,
	}

	return PairGeometry{
		BoundaryX:           boundary,
		LeftRect:            leftRect,
		RightRect:           rightRect,
		EffectiveLeftScale:  leftScale,
		EffectiveRightScale: rightScale,
	}, nil
}

func (v Validation) rectFor(m Monitor) Rect {
	if m.Name == v.Left.Name {
		return v.Geometry.LeftRect
	}
	if m.Name == v.Right.Name {
		return v.Geometry.RightRect
	}
	return Rect{}
}

func physicalDistanceFromBottomInRect(m Monitor, rect Rect, y float64) (float64, error) {
	if m.PhysicalHeight <= 0 {
		return 0, errors.New("physical height must be positive")
	}
	if rect.H <= 0 {
		return 0, errors.New("coordinate height must be positive")
	}
	bottom := rect.Y + rect.H
	distanceUnits := bottom - y
	return distanceUnits * float64(m.PhysicalHeight) / rect.H, nil
}

func mapPhysicalHeightInRects(source, destination Monitor, sourceRect, destinationRect Rect, sourceY float64) (float64, bool, error) {
	distanceMM, err := physicalDistanceFromBottomInRect(source, sourceRect, sourceY)
	if err != nil {
		return 0, false, err
	}
	sharedHeight := math.Min(float64(source.PhysicalHeight), float64(destination.PhysicalHeight))
	const epsilon = 0.5
	if distanceMM < -epsilon || distanceMM > sharedHeight+epsilon {
		return 0, false, nil
	}

	if destinationRect.H <= 0 || destination.PhysicalHeight <= 0 {
		return 0, false, errors.New("destination geometry is invalid")
	}
	destinationDistance := distanceMM * destinationRect.H / float64(destination.PhysicalHeight)
	destinationBottom := destinationRect.Y + destinationRect.H
	y := destinationBottom - destinationDistance
	return clamp(y, destinationRect.Y+1, destinationBottom-1), true, nil
}

func mapPhysicalHeight(source, destination Monitor, mode CoordinateMode, sourceY float64) (float64, bool, error) {
	sourceW, sourceH := coordDimensions(source, mode)
	destinationW, destinationH := coordDimensions(destination, mode)
	return mapPhysicalHeightInRects(
		source,
		destination,
		Rect{X: float64(source.X), Y: float64(source.Y), W: sourceW, H: sourceH},
		Rect{X: float64(destination.X), Y: float64(destination.Y), W: destinationW, H: destinationH},
		sourceY,
	)
}

func clamp(value, minValue, maxValue float64) float64 {
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

type cursorSample struct {
	Point   Cursor
	Monitor string
	At      time.Time
}

type warpRecord struct {
	Point Cursor
	At    time.Time
}

type Daemon struct {
	mu sync.RWMutex

	client HyprClient
	store  *Store
	paths  Paths
	logger *slog.Logger

	state       RuntimeState
	profile     *Profile
	validation  *Validation
	previous    *cursorSample
	lastWarp    warpRecord
	cursorFails int
	dryRun      bool
}

func NewDaemon(store *Store, paths Paths, pollHz int, dryRun bool, logger *slog.Logger) *Daemon {
	return &Daemon{
		client: HyprClient{},
		store:  store,
		paths:  paths,
		logger: logger,
		dryRun: dryRun,
		state: RuntimeState{
			DaemonRunning: true,
			State:         "disabled",
			PollHz:        pollHz,
			DryRun:        dryRun,
		},
	}
}

func (d *Daemon) Snapshot() RuntimeState {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.state
}

func (d *Daemon) persistStateLocked() {
	if err := os.MkdirAll(d.paths.RuntimeDir, 0o700); err != nil {
		d.logger.Warn("cannot create runtime directory", "error", err)
		return
	}
	data, err := json.MarshalIndent(d.state, "", "  ")
	if err != nil {
		d.logger.Warn("cannot encode runtime state", "error", err)
		return
	}
	data = append(data, '\n')
	if err := os.WriteFile(d.paths.StateFile, data, 0o600); err != nil {
		d.logger.Warn("cannot persist runtime state", "error", err)
	}
}

func (d *Daemon) Activate(ctx context.Context, name string) error {
	cfg, err := d.store.Load()
	if err != nil {
		return err
	}
	profile, ok := cfg.Profiles[name]
	if !ok {
		return fmt.Errorf("profile %q does not exist", name)
	}
	monitors, err := d.client.Monitors(ctx)
	if err != nil {
		return err
	}
	validation, err := validateProfile(profile, monitors)
	if err != nil {
		return fmt.Errorf("profile %q is unsafe to activate: %w", name, err)
	}

	d.mu.Lock()
	d.profile = &profile
	d.validation = &validation
	d.previous = nil
	d.cursorFails = 0
	d.state.State = "active"
	d.state.Profile = name
	d.state.Valid = true
	d.state.Reason = ""
	d.state.LastValidationTime = time.Now()
	d.persistStateLocked()
	d.mu.Unlock()

	d.logger.Info("profile activated", "profile", name, "left", validation.Left.Name, "right", validation.Right.Name, "coordinate_mode", validation.Mode)
	return nil
}

func (d *Daemon) Disable(reason string, automatic bool) {
	d.mu.Lock()
	profileName := d.state.Profile
	d.profile = nil
	d.validation = nil
	d.previous = nil
	d.state.Valid = false
	d.state.Reason = reason
	if automatic && profileName != "" {
		d.state.State = "disabled_with_reason"
	} else {
		d.state.State = "disabled"
		d.state.Profile = ""
	}
	d.persistStateLocked()
	d.mu.Unlock()

	if reason == "" {
		d.logger.Info("remapping disabled")
	} else {
		d.logger.Warn("remapping disabled", "reason", reason, "profile", profileName)
	}
}

func (d *Daemon) Reload(ctx context.Context) error {
	state := d.Snapshot()
	if state.Profile == "" || state.State != "active" {
		return nil
	}
	return d.Activate(ctx, state.Profile)
}

func (d *Daemon) revalidate(ctx context.Context) {
	d.mu.RLock()
	if d.profile == nil || d.state.State != "active" {
		d.mu.RUnlock()
		return
	}
	profile := *d.profile
	profileName := d.state.Profile
	d.mu.RUnlock()

	monitors, err := d.client.Monitors(ctx)
	if err != nil {
		d.Disable("Hyprland monitor IPC failed: "+err.Error(), true)
		return
	}
	validation, err := validateProfile(profile, monitors)
	if err != nil {
		d.Disable(err.Error(), true)
		return
	}

	d.mu.Lock()
	if d.state.State == "active" && d.state.Profile == profileName {
		d.validation = &validation
		d.state.Valid = true
		d.state.LastValidationTime = time.Now()
		d.persistStateLocked()
	}
	d.mu.Unlock()
}

func (d *Daemon) processCursor(ctx context.Context) {
	d.mu.RLock()
	if d.validation == nil || d.state.State != "active" {
		d.mu.RUnlock()
		return
	}
	validation := *d.validation
	previous := d.previous
	lastWarp := d.lastWarp
	d.mu.RUnlock()

	point, err := d.client.Cursor(ctx)
	if err != nil {
		d.mu.Lock()
		d.cursorFails++
		failures := d.cursorFails
		d.mu.Unlock()
		if failures >= 3 {
			d.Disable("cursor sampling failed repeatedly: "+err.Error(), true)
		}
		return
	}

	now := time.Now()
	currentMonitor := monitorAt(point, validation)
	current := &cursorSample{Point: point, Monitor: currentMonitor, At: now}

	if now.Sub(lastWarp.At) < 90*time.Millisecond && distance(point, lastWarp.Point) <= 6 {
		d.setPrevious(current)
		return
	}
	if previous == nil {
		d.setPrevious(current)
		return
	}
	if previous.Monitor != "" && previous.Monitor == currentMonitor {
		if d.handleEdgeAttempt(ctx, previous, current, validation) {
			return
		}
		d.setPrevious(current)
		return
	}
	if previous.Monitor == "" || currentMonitor == "" {
		d.setPrevious(current)
		return
	}

	var source, destination Monitor
	var sourceName, destinationName string
	var leftToRight bool
	switch {
	case previous.Monitor == "left" && currentMonitor == "right":
		source, destination = validation.Left, validation.Right
		sourceName, destinationName = validation.Left.Name, validation.Right.Name
		leftToRight = true
	case previous.Monitor == "right" && currentMonitor == "left":
		source, destination = validation.Right, validation.Left
		sourceName, destinationName = validation.Right.Name, validation.Left.Name
		leftToRight = false
	default:
		d.setPrevious(current)
		return
	}

	boundaryX := validation.Geometry.BoundaryX
	crossingY := interpolateYAtX(previous.Point, point, boundaryX)
	mappedY, valid, mapErr := mapPhysicalHeightInRects(source, destination, validation.rectFor(source), validation.rectFor(destination), crossingY)
	if mapErr != nil {
		d.Disable("geometry mapping failed: "+mapErr.Error(), true)
		return
	}

	if !valid {
		sourceRect := validation.rectFor(source)
		targetX := sourceRect.X + sourceRect.W - 3
		if !leftToRight {
			targetX = sourceRect.X + 2
		}
		targetY := clamp(crossingY, sourceRect.Y+1, sourceRect.Y+sourceRect.H-1)
		if err := d.warp(ctx, Cursor{X: targetX, Y: targetY}, sourceName, sourceName, true); err != nil {
			d.handleWarpFailure(err)
			return
		}
		d.logger.Debug("dead-zone crossing blocked", "monitor", sourceName, "y", crossingY)
		return
	}

	destinationRect := validation.rectFor(destination)
	targetX := destinationRect.X + 2
	if !leftToRight {
		targetX = destinationRect.X + destinationRect.W - 3
	}
	if err := d.warp(ctx, Cursor{X: targetX, Y: mappedY}, sourceName, destinationName, false); err != nil {
		d.handleWarpFailure(err)
		return
	}
}

func (d *Daemon) handleEdgeAttempt(ctx context.Context, previous, current *cursorSample, validation Validation) bool {
	const edgeThreshold = 2.5
	const movementThreshold = 0.01

	var source, destination Monitor
	var sourceName, destinationName string
	var leftToRight bool

	switch current.Monitor {
	case "left":
		source, destination = validation.Left, validation.Right
		sourceName, destinationName = validation.Left.Name, validation.Right.Name
		leftToRight = true
	case "right":
		source, destination = validation.Right, validation.Left
		sourceName, destinationName = validation.Right.Name, validation.Left.Name
		leftToRight = false
	default:
		return false
	}

	sourceRect := validation.rectFor(source)
	attempting := false
	if leftToRight {
		edge := sourceRect.X + sourceRect.W
		attempting = current.Point.X >= edge-edgeThreshold && current.Point.X > previous.Point.X+movementThreshold
	} else {
		edge := sourceRect.X
		attempting = current.Point.X <= edge+edgeThreshold && current.Point.X < previous.Point.X-movementThreshold
	}
	if !attempting {
		return false
	}

	mappedY, valid, err := mapPhysicalHeightInRects(source, destination, validation.rectFor(source), validation.rectFor(destination), current.Point.Y)
	if err != nil {
		d.Disable("geometry mapping failed: "+err.Error(), true)
		return true
	}
	if !valid {
		targetX := sourceRect.X + sourceRect.W - 3
		if !leftToRight {
			targetX = sourceRect.X + 2
		}
		targetY := clamp(current.Point.Y, sourceRect.Y+1, sourceRect.Y+sourceRect.H-1)
		if err := d.warp(ctx, Cursor{X: targetX, Y: targetY}, sourceName, sourceName, true); err != nil {
			d.handleWarpFailure(err)
		}
		d.logger.Debug("dead-zone edge attempt blocked", "monitor", sourceName, "y", current.Point.Y)
		return true
	}

	destinationRect := validation.rectFor(destination)
	targetX := destinationRect.X + 2
	if !leftToRight {
		targetX = destinationRect.X + destinationRect.W - 3
	}
	if err := d.warp(ctx, Cursor{X: targetX, Y: mappedY}, sourceName, destinationName, false); err != nil {
		d.handleWarpFailure(err)
	}
	return true
}

func (d *Daemon) setPrevious(sample *cursorSample) {
	d.mu.Lock()
	d.previous = sample
	d.cursorFails = 0
	d.mu.Unlock()
}

func (d *Daemon) warp(ctx context.Context, target Cursor, source, destination string, wall bool) error {
	if d.dryRun {
		d.logger.Info("dry-run warp", "x", math.Round(target.X), "y", math.Round(target.Y), "source", source, "destination", destination, "wall", wall)
	} else if err := d.client.Warp(ctx, target.X, target.Y); err != nil {
		return err
	}

	now := time.Now()
	d.mu.Lock()
	d.lastWarp = warpRecord{Point: target, At: now}
	d.previous = &cursorSample{Point: target, Monitor: monitorNameForDestination(source, destination, wall, d.validation), At: now}
	d.cursorFails = 0
	d.state.LastRemapTime = now
	d.state.LastSource = source
	d.state.LastDestination = destination
	d.state.RemapCount++
	d.persistStateLocked()
	d.mu.Unlock()

	if !wall {
		d.logger.Debug("cursor remapped", "source", source, "destination", destination, "x", target.X, "y", target.Y)
	}
	return nil
}

func monitorNameForDestination(source, destination string, wall bool, validation *Validation) string {
	name := destination
	if wall {
		name = source
	}
	if validation == nil {
		return ""
	}
	if validation.Left.Name == name {
		return "left"
	}
	if validation.Right.Name == name {
		return "right"
	}
	return ""
}

func (d *Daemon) handleWarpFailure(err error) {
	d.mu.Lock()
	d.state.Reason = err.Error()
	d.persistStateLocked()
	d.mu.Unlock()
	d.Disable("cursor warp failed: "+err.Error(), true)
}

func monitorAt(point Cursor, validation Validation) string {
	// Resolve the shared seam explicitly so a rounded scale can never create an
	// artificial overlap where both rectangles claim the same point.
	if point.X < validation.Geometry.BoundaryX {
		if validation.Geometry.LeftRect.Contains(point) {
			return "left"
		}
		return ""
	}
	if validation.Geometry.RightRect.Contains(point) {
		return "right"
	}
	return ""
}

func interpolateYAtX(previous, current Cursor, x float64) float64 {
	deltaX := current.X - previous.X
	if math.Abs(deltaX) < 0.001 {
		return previous.Y
	}
	t := (x - previous.X) / deltaX
	t = clamp(t, 0, 1)
	return previous.Y + t*(current.Y-previous.Y)
}

func distance(a, b Cursor) float64 {
	return math.Hypot(a.X-b.X, a.Y-b.Y)
}

func (d *Daemon) Run(ctx context.Context, initialProfile string) error {
	if err := os.MkdirAll(d.paths.RuntimeDir, 0o700); err != nil {
		return fmt.Errorf("create runtime directory: %w", err)
	}
	listener, err := listenControlSocket(d.paths.ControlSock)
	if err != nil {
		return err
	}
	defer func() {
		listener.Close()
		os.Remove(d.paths.ControlSock)
		os.Remove(d.paths.StateFile)
	}()

	d.mu.Lock()
	d.persistStateLocked()
	d.mu.Unlock()

	go d.serveControl(ctx, listener)
	if initialProfile != "" {
		if err := d.Activate(ctx, initialProfile); err != nil {
			return err
		}
	}

	pollInterval := time.Second / time.Duration(d.state.PollHz)
	cursorTicker := time.NewTicker(pollInterval)
	validationTicker := time.NewTicker(time.Second)
	defer cursorTicker.Stop()
	defer validationTicker.Stop()

	d.logger.Info("daemon started", "poll_hz", d.state.PollHz, "dry_run", d.dryRun, "socket", d.paths.ControlSock)
	for {
		select {
		case <-ctx.Done():
			d.logger.Info("daemon stopping")
			return nil
		case <-cursorTicker.C:
			d.processCursor(ctx)
		case <-validationTicker.C:
			d.revalidate(ctx)
		}
	}
}

func listenControlSocket(path string) (net.Listener, error) {
	if conn, err := net.DialTimeout("unix", path, 150*time.Millisecond); err == nil {
		conn.Close()
		return nil, fmt.Errorf("daemon already running at %s", path)
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("remove stale control socket: %w", err)
	}
	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, fmt.Errorf("listen on control socket: %w", err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		listener.Close()
		return nil, fmt.Errorf("chmod control socket: %w", err)
	}
	return listener, nil
}

func (d *Daemon) serveControl(ctx context.Context, listener net.Listener) {
	go func() {
		<-ctx.Done()
		listener.Close()
	}()

	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			d.logger.Warn("control socket accept failed", "error", err)
			continue
		}
		go d.handleControlConnection(ctx, conn)
	}
}

func (d *Daemon) handleControlConnection(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))

	decoder := json.NewDecoder(io.LimitReader(conn, 64*1024))
	encoder := json.NewEncoder(conn)
	var request ControlRequest
	if err := decoder.Decode(&request); err != nil {
		_ = encoder.Encode(ControlResponse{OK: false, Message: "invalid request: " + err.Error(), Status: d.Snapshot()})
		return
	}

	response := ControlResponse{OK: true}
	switch strings.ToLower(strings.TrimSpace(request.Command)) {
	case "status":
		response.Message = "status"
	case "enable":
		if request.Profile == "" {
			response.OK = false
			response.Message = "profile is required"
		} else if err := d.Activate(ctx, request.Profile); err != nil {
			response.OK = false
			response.Message = err.Error()
		} else {
			response.Message = "profile enabled"
		}
	case "disable":
		d.Disable("", false)
		response.Message = "remapping disabled"
	case "reload":
		if err := d.Reload(ctx); err != nil {
			response.OK = false
			response.Message = err.Error()
		} else {
			response.Message = "configuration reloaded"
		}
	default:
		response.OK = false
		response.Message = "unknown command"
	}
	response.Status = d.Snapshot()
	_ = encoder.Encode(response)
}

func sendControl(paths Paths, request ControlRequest) (ControlResponse, error) {
	conn, err := net.DialTimeout("unix", paths.ControlSock, 500*time.Millisecond)
	if err != nil {
		return ControlResponse{}, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))

	if err := json.NewEncoder(conn).Encode(request); err != nil {
		return ControlResponse{}, fmt.Errorf("send control request: %w", err)
	}
	var response ControlResponse
	if err := json.NewDecoder(conn).Decode(&response); err != nil {
		return ControlResponse{}, fmt.Errorf("read control response: %w", err)
	}
	return response, nil
}

func main() {
	if len(os.Args) < 2 {
		printUsage(os.Stderr)
		os.Exit(2)
	}

	paths, err := resolvePaths()
	if err != nil {
		fatal(err)
	}
	store := NewStore(paths)
	ctx := context.Background()

	switch os.Args[1] {
	case "profile":
		err = runProfileCommand(ctx, store, os.Args[2:])
	case "validate":
		err = runValidate(ctx, store, os.Args[2:])
	case "debug":
		err = runDebug(ctx, os.Args[2:])
	case "daemon":
		err = runDaemon(store, paths, os.Args[2:])
	case "enable", "disable", "status", "reload":
		err = runControl(paths, os.Args[1], os.Args[2:])
	case "paths":
		err = printJSON(paths)
	case "self-test":
		err = runSelfTest()
	case "help", "--help", "-h":
		printUsage(os.Stdout)
		return
	default:
		printUsage(os.Stderr)
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fatal(err)
	}
}

func runProfileCommand(ctx context.Context, store *Store, args []string) error {
	if len(args) < 1 {
		return errors.New("usage: desk-cursor profile <save|list|show|delete> ...")
	}
	switch args[0] {
	case "save":
		return profileSave(ctx, store, args[1:])
	case "list":
		return profileList(store)
	case "show":
		if len(args) != 2 {
			return errors.New("usage: desk-cursor profile show <name>")
		}
		return profileShow(store, args[1])
	case "delete":
		if len(args) != 2 {
			return errors.New("usage: desk-cursor profile delete <name>")
		}
		return profileDelete(store, args[1])
	default:
		return fmt.Errorf("unknown profile command %q", args[0])
	}
}

func profileSave(ctx context.Context, store *Store, args []string) error {
	if len(args) < 1 {
		return errors.New("usage: desk-cursor profile save <name> [--left CONNECTOR] [--right CONNECTOR] [--align bottom]")
	}
	name := strings.TrimSpace(args[0])
	if name == "" || strings.ContainsAny(name, "/\\\x00") {
		return errors.New("profile name is invalid")
	}

	flags := flag.NewFlagSet("profile save", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	leftName := flags.String("left", "", "left monitor connector")
	rightName := flags.String("right", "", "right monitor connector")
	alignment := flags.String("align", "bottom", "physical alignment")
	if err := flags.Parse(args[1:]); err != nil {
		return err
	}
	if *alignment != "bottom" {
		return errors.New("only --align bottom is supported")
	}

	monitors, err := (HyprClient{}).Monitors(ctx)
	if err != nil {
		return err
	}
	active := activeMonitors(monitors)
	if len(active) != 2 {
		return fmt.Errorf("profile capture requires exactly 2 active monitors, found %d", len(active))
	}
	for _, monitor := range active {
		if mirrorEnabled(monitor) {
			return fmt.Errorf("cannot capture mirrored monitor %s", monitor.Name)
		}
		if monitor.Transform != 0 {
			return fmt.Errorf("cannot capture monitor %s with transform %d", monitor.Name, monitor.Transform)
		}
	}

	left, right, err := chooseLeftRight(active, *leftName, *rightName)
	if err != nil {
		return err
	}
	mode := inferCoordinateMode(left, right)
	profile := Profile{
		Alignment:      "bottom",
		CoordinateMode: mode,
		Left:           captureSpec(left),
		Right:          captureSpec(right),
		RelativeX:      right.X - left.X,
		RelativeY:      right.Y - left.Y,
		CapturedAt:     time.Now(),
	}
	if _, err := validateProfile(profile, monitors); err != nil {
		return fmt.Errorf("current arrangement cannot be saved safely: %w", err)
	}

	cfg, err := store.Load()
	if err != nil {
		return err
	}
	cfg.Profiles[name] = profile
	if err := store.Save(cfg); err != nil {
		return err
	}
	fmt.Printf("saved profile %q (%s -> %s, coordinate mode %s)\n", name, left.Name, right.Name, mode)
	return nil
}

func chooseLeftRight(monitors []Monitor, leftName, rightName string) (Monitor, Monitor, error) {
	if leftName == "" && rightName == "" {
		copyMonitors := append([]Monitor(nil), monitors...)
		sort.Slice(copyMonitors, func(i, j int) bool { return copyMonitors[i].X < copyMonitors[j].X })
		if copyMonitors[0].X == copyMonitors[1].X {
			return Monitor{}, Monitor{}, errors.New("cannot infer left and right monitors because their X positions are equal")
		}
		return copyMonitors[0], copyMonitors[1], nil
	}
	if leftName == "" || rightName == "" {
		return Monitor{}, Monitor{}, errors.New("provide both --left and --right, or neither")
	}
	left, leftOK := findMonitorByName(monitors, leftName)
	right, rightOK := findMonitorByName(monitors, rightName)
	if !leftOK {
		return Monitor{}, Monitor{}, fmt.Errorf("left connector %q is not active", leftName)
	}
	if !rightOK {
		return Monitor{}, Monitor{}, fmt.Errorf("right connector %q is not active", rightName)
	}
	if left.Name == right.Name {
		return Monitor{}, Monitor{}, errors.New("left and right connectors must differ")
	}
	if left.X >= right.X {
		return Monitor{}, Monitor{}, fmt.Errorf("%s is not currently left of %s", left.Name, right.Name)
	}
	return left, right, nil
}

func findMonitorByName(monitors []Monitor, name string) (Monitor, bool) {
	for _, monitor := range monitors {
		if monitor.Name == name {
			return monitor, true
		}
	}
	return Monitor{}, false
}

func profileList(store *Store) error {
	cfg, err := store.Load()
	if err != nil {
		return err
	}
	names := make([]string, 0, len(cfg.Profiles))
	for name := range cfg.Profiles {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		profile := cfg.Profiles[name]
		fmt.Printf("%s\t%s -> %s\t%s\n", name, profile.Left.Description, profile.Right.Description, profile.CoordinateMode)
	}
	return nil
}

func profileShow(store *Store, name string) error {
	cfg, err := store.Load()
	if err != nil {
		return err
	}
	profile, ok := cfg.Profiles[name]
	if !ok {
		return fmt.Errorf("profile %q does not exist", name)
	}
	return printJSON(profile)
}

func profileDelete(store *Store, name string) error {
	cfg, err := store.Load()
	if err != nil {
		return err
	}
	if _, ok := cfg.Profiles[name]; !ok {
		return fmt.Errorf("profile %q does not exist", name)
	}
	delete(cfg.Profiles, name)
	if err := store.Save(cfg); err != nil {
		return err
	}
	fmt.Printf("deleted profile %q\n", name)
	return nil
}

func runValidate(ctx context.Context, store *Store, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: desk-cursor validate <profile>")
	}
	cfg, err := store.Load()
	if err != nil {
		return err
	}
	profile, ok := cfg.Profiles[args[0]]
	if !ok {
		return fmt.Errorf("profile %q does not exist", args[0])
	}
	monitors, err := (HyprClient{}).Monitors(ctx)
	if err != nil {
		return err
	}
	validation, err := validateProfile(profile, monitors)
	if err != nil {
		return err
	}
	return printJSON(map[string]any{
		"valid":                 true,
		"left_connector":        validation.Left.Name,
		"right_connector":       validation.Right.Name,
		"coordinate_mode":       validation.Mode,
		"boundary_x":            validation.Geometry.BoundaryX,
		"effective_left_scale":  validation.Geometry.EffectiveLeftScale,
		"effective_right_scale": validation.Geometry.EffectiveRightScale,
	})
}

func runDebug(ctx context.Context, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: desk-cursor debug <monitors|cursor>")
	}
	client := HyprClient{}
	switch args[0] {
	case "monitors":
		monitors, err := client.Monitors(ctx)
		if err != nil {
			return err
		}
		active := activeMonitors(monitors)
		result := map[string]any{"monitors": monitors}
		if len(active) == 2 {
			left, right, err := chooseLeftRight(active, "", "")
			if err == nil {
				mode := inferCoordinateMode(left, right)
				result["inferred_coordinate_mode"] = mode
				geometry, geometryErr := pairGeometry(left, right, mode)
				if geometryErr != nil {
					result["geometry_error"] = geometryErr.Error()
				} else {
					result["boundary_x"] = geometry.BoundaryX
					result["effective_left_scale"] = geometry.EffectiveLeftScale
					result["effective_right_scale"] = geometry.EffectiveRightScale
					result["left_rect"] = geometry.LeftRect
					result["right_rect"] = geometry.RightRect
				}
			}
		}
		return printJSON(result)
	case "cursor":
		cursor, err := client.Cursor(ctx)
		if err != nil {
			return err
		}
		return printJSON(cursor)
	default:
		return fmt.Errorf("unknown debug command %q", args[0])
	}
}

func runDaemon(store *Store, paths Paths, args []string) error {
	flags := flag.NewFlagSet("daemon", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	profile := flags.String("profile", "", "explicitly activate this profile at startup")
	pollHz := flags.Int("hz", defaultPollHz, "cursor polling frequency")
	dryRun := flags.Bool("dry-run", false, "log warps without moving the cursor")
	logLevel := flags.String("log-level", "info", "debug, info, warn, or error")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *pollHz < 1 || *pollHz > maxPollHz {
		return fmt.Errorf("--hz must be between 1 and %d", maxPollHz)
	}
	level, err := parseLogLevel(*logLevel)
	if err != nil {
		return err
	}
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	daemon := NewDaemon(store, paths, *pollHz, *dryRun, logger)

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	return daemon.Run(ctx, *profile)
}

func parseLogLevel(value string) (slog.Level, error) {
	switch strings.ToLower(value) {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn", "warning":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return 0, fmt.Errorf("invalid log level %q", value)
	}
}

func runControl(paths Paths, command string, args []string) error {
	request := ControlRequest{Command: command}
	if command == "enable" {
		if len(args) != 1 {
			return errors.New("usage: desk-cursor enable <profile>")
		}
		request.Profile = args[0]
	} else if len(args) != 0 {
		return fmt.Errorf("usage: desk-cursor %s", command)
	}

	response, err := sendControl(paths, request)
	if err != nil {
		if command == "status" {
			return printJSON(RuntimeState{DaemonRunning: false, State: "stopped"})
		}
		return fmt.Errorf("daemon is not reachable at %s: %w", paths.ControlSock, err)
	}
	if err := printJSON(response); err != nil {
		return err
	}
	if !response.OK {
		return errors.New(response.Message)
	}
	return nil
}

func runSelfTest() error {
	left := Monitor{
		Name: "HDMI-A-1", Width: 2560, Height: 1440,
		PhysicalWidth: 530, PhysicalHeight: 300,
		X: -2560, Y: 0, Scale: 1.33,
	}
	right := Monitor{
		Name: "eDP-1", Width: 2560, Height: 1600,
		PhysicalWidth: 340, PhysicalHeight: 220,
		X: 0, Y: 0, Scale: 1.33,
	}
	mode := inferCoordinateMode(left, right)
	if mode != CoordinateNative {
		return fmt.Errorf("coordinate mode: got %s, want native", mode)
	}

	tests := []struct {
		name        string
		source      Monitor
		destination Monitor
		sourceY     float64
		wantValid   bool
		wantY       float64
		tolerance   float64
	}{
		{name: "bottom left to right", source: left, destination: right, sourceY: 1440, wantValid: true, wantY: 1599, tolerance: 1.1},
		{name: "150mm left to right", source: left, destination: right, sourceY: 720, wantValid: true, wantY: 509.09, tolerance: 0.1},
		{name: "left upper dead zone", source: left, destination: right, sourceY: 240, wantValid: false},
		{name: "110mm right to left", source: right, destination: left, sourceY: 800, wantValid: true, wantY: 912, tolerance: 0.1},
	}

	for _, test := range tests {
		gotY, valid, err := mapPhysicalHeight(test.source, test.destination, mode, test.sourceY)
		if err != nil {
			return fmt.Errorf("%s: %w", test.name, err)
		}
		if valid != test.wantValid {
			return fmt.Errorf("%s: valid=%v, want %v", test.name, valid, test.wantValid)
		}
		if valid && math.Abs(gotY-test.wantY) > test.tolerance {
			return fmt.Errorf("%s: y=%.3f, want %.3f", test.name, gotY, test.wantY)
		}
	}

	logicalLeft := left
	logicalLeft.X = -1920
	logicalRight := right
	logicalRight.X = 0
	logicalMode := inferCoordinateMode(logicalLeft, logicalRight)
	if logicalMode != CoordinateLogical {
		return fmt.Errorf("rounded-scale coordinate mode: got %s, want logical", logicalMode)
	}
	geometry, err := pairGeometry(logicalLeft, logicalRight, logicalMode)
	if err != nil {
		return fmt.Errorf("rounded-scale pair geometry: %w", err)
	}
	if math.Abs(geometry.BoundaryX) > 0.001 || math.Abs(geometry.LeftRect.W-1920) > 0.001 || math.Abs(geometry.RightRect.W-1920) > 0.001 {
		return fmt.Errorf("rounded-scale geometry mismatch: boundary=%.3f leftW=%.3f rightW=%.3f", geometry.BoundaryX, geometry.LeftRect.W, geometry.RightRect.W)
	}
	if math.Abs(geometry.LeftRect.H-1080) > 0.001 || math.Abs(geometry.RightRect.H-1200) > 0.001 {
		return fmt.Errorf("rounded-scale heights mismatch: leftH=%.3f rightH=%.3f", geometry.LeftRect.H, geometry.RightRect.H)
	}
	if monitorAt(Cursor{X: -0.1, Y: 500}, Validation{Left: logicalLeft, Right: logicalRight, Mode: logicalMode, Geometry: geometry}) != "left" {
		return errors.New("point left of seam was not assigned to left monitor")
	}
	if monitorAt(Cursor{X: 0, Y: 500}, Validation{Left: logicalLeft, Right: logicalRight, Mode: logicalMode, Geometry: geometry}) != "right" {
		return errors.New("point on seam was not assigned to right monitor")
	}

	fmt.Println("self-test: PASS")
	return nil
}

func printJSON(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, `desk-cursor — physical-height cursor remapping for a saved Hyprland desk profile

Usage:
  desk-cursor profile save <name> [--left HDMI-A-1 --right eDP-1 --align bottom]
  desk-cursor profile list
  desk-cursor profile show <name>
  desk-cursor profile delete <name>

  desk-cursor validate <name>
  desk-cursor debug monitors
  desk-cursor debug cursor

  desk-cursor daemon [--profile <name>] [--hz 120] [--dry-run] [--log-level debug]
  desk-cursor enable <name>
  desk-cursor disable
  desk-cursor status
  desk-cursor reload

  desk-cursor paths
  desk-cursor self-test

The daemon starts disabled unless --profile is explicitly supplied or the enable
command is sent over its Unix control socket.`)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
