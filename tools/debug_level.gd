extends SceneTree
## Usage: godot --headless --fixed-fps 60 --path . -s res://tools/debug_level.gd -- CODE [from_module]
func _initialize(): _run.call_deferred()
func _run():
	var args := OS.get_cmdline_user_args()
	var cfg := GeneratorConfig.from_code(args[0])
	var from := int(args[1]) if args.size() > 1 else 0
	var level := TrackGenerator.new().generate(cfg)
	for p in level.placements: print(p.index, " ", p.def.id, "/", p.style, " var=", p.variant, " vlo_in=", snappedf(p.v_lo_in,0.01), " vhi_in=", snappedf(p.v_hi_in,0.01), " cp=", p.checkpoint, " limits=", p.limits)
	var h := SimHarness.new(self, level)
	h.autopilot = Autopilot.new()
	var f := func(sim):
		return 0.0
	var last := -1
	while true:
		var r = await h.run(h.ticks / 60.0 + 0.25)
		if r.result != "timeout":
			print(r); break
		if h.tracker.current >= from:
			print("t=%.2f mod=%d(%s) lt=%.2f v=%.2f vel=%s off=%s steer=%.2f" % [h.ticks/60.0, h.tracker.current, level.placements[h.tracker.current].def.id, h.tracker.local_t, h.marble.speed(), str(h.marble.linear_velocity.snappedf(0.01)), str(h.tracker.offset.snappedf(0.01)), h.marble.steer])
	quit()
