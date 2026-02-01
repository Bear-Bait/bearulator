/*
BEARULATOR: Harmonium Interface v2.1
Full-featured GUI for the 32-band filterbank synth

v2.1 ADDITIONS:
- Vocoder mode controls (Track selector when Source = 16)
- Input gain control for vocoder
- Start/Stop routing buttons

Usage:
  ~makeHarmoniumGUI.();
*/

~makeHarmoniumGUI = {
	// === ALL VARIABLES DECLARED AT TOP ===
	var window, ctrlScroll, ctrlView, gridScroll, gridView;
	var buttons, sliders;
	var maskArray, gainArray;
	var maxPartials, nextY;
	var wWidth, wHeight, ctrlW, btnW, btnH, slH, slW;
	var rowH, labW, nbW, gap;
	var fLbl, fVal;
	var colors;
	var setMaskAt, setGainAt, setAllMasks, refreshButtons, refreshSliders;
	var mkRow, mkFreqRow;
	var vocoderSection, vocoderTrackMenu, vocoderGainSlider, vocoderRouteBtn;
	var srcMenu, updateVocoderVisibility;
	var vocoderActiveTrack;  // Track which track is currently hijacked (nil if none)

	// === CONSTANTS ===
	maxPartials = 32;
	nextY = 8;
	wWidth = 1100;
	wHeight = 750;
	ctrlW = 380;
	btnW = 28;
	btnH = 20;
	slH = 120;
	slW = 14;
	rowH = 28;
	labW = 100;
	nbW = 55;
	gap = 6;
	fLbl = Font("DejaVu Sans Mono", 10);
	fVal = Font("DejaVu Sans Mono", 9);

	// Doom Material colors
	colors = (
		bg: Color.fromHexString("#262938"),
		fg: Color.fromHexString("#EEFFFF"),
		black: Color.fromHexString("#171F24"),
		cyan: Color.fromHexString("#89DDFF"),
		yellow: Color.fromHexString("#ffcb6b"),
		green: Color.fromHexString("#c3e88d"),
		red: Color.fromHexString("#ff5370"),
		magenta: Color.fromHexString("#c792ea"),
		brightBlack: Color.fromHexString("#37474F")
	);

	// Initialize arrays from current params
	maskArray = ~harmoniumParams[\mask].copy;
	gainArray = ~harmoniumParams[\gains].copy;

	// === HELPER FUNCTIONS ===
	setMaskAt = { |i, v|
		maskArray[i] = v.clip(0, 1);
		~harmoniumSetParam.(\mask, maskArray);
	};

	setGainAt = { |i, v|
		gainArray[i] = v.clip(0, 1);
		~harmoniumSetParam.(\gains, gainArray);
	};

	setAllMasks = { |v|
		maxPartials.do({ |i| maskArray[i] = v });
	};

	refreshButtons = { |btns|
		btns.do({ |b, i| if(b.notNil, { b.value_(maskArray[i]) }) });
	};

	refreshSliders = { |slds|
		slds.do({ |s, i| if(s.notNil, { s.value_(gainArray[i]) }) });
	};

	// Row builder helper
	mkRow = { |label, min, max, init, step, decimals, param|
		var slw, grp, nb, sl, v, isInt, sStep;
		isInt = step.notNil and: { step >= 1 };
		sStep = step ?? { (max - min) / 1000 };
		slw = ctrlW - 24 - labW - nbW - gap;

		grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW - 16, rowH));

		StaticText(grp, Rect(0, 4, labW, rowH - 10))
			.string_(label)
			.stringColor_(colors.fg)
			.font_(fLbl);

		nb = NumberBox(grp, Rect(labW, 2, nbW, rowH - 6))
			.stringColor_(colors.fg)
			.background_(colors.black)
			.font_(fVal)
			.clipLo_(min).clipHi_(max)
			.decimals_(decimals)
			.step_(sStep);

		sl = Slider(grp, Rect(labW + nbW + gap, 4, slw, rowH - 10));

		sl.action_({
			var vv;
			vv = sl.value.linlin(0, 1, min, max);
			if(isInt, { vv = vv.round(sStep) }, { vv = (vv / sStep).round * sStep });
			vv = vv.clip(min, max);
			nb.value_(vv);
			~harmoniumSetParam.(param, vv);
		});

		nb.action_({ |box|
			var vv;
			vv = box.value.clip(min, max);
			if(isInt, { vv = vv.round(sStep); box.value_(vv) });
			sl.value_(vv.linlin(min, max, 0, 1).clip(0, 1));
			~harmoniumSetParam.(param, vv);
		});

		v = init.clip(min, max);
		if(isInt, { v = v.round(sStep) });
		nb.value_(v);
		sl.value_(v.linlin(min, max, 0, 1).clip(0, 1));
		~harmoniumSetParam.(param, v);

		nextY = nextY + rowH;
	};

	// Frequency row (exponential)
	mkFreqRow = { |label, min, max, init, param|
		var slw, grp, nb, sl, v;
		var fromSlider, toSlider;

		fromSlider = { |sv| (min * ((max / min).pow(sv))).clip(min, max) };
		toSlider = { |hz| ((hz.clip(min, max) / min).log) / ((max / min).log) };

		slw = ctrlW - 24 - labW - nbW - gap;
		grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW - 16, rowH));

		StaticText(grp, Rect(0, 4, labW, rowH - 10))
			.string_(label)
			.stringColor_(colors.fg)
			.font_(fLbl);

		nb = NumberBox(grp, Rect(labW, 2, nbW, rowH - 6))
			.stringColor_(colors.fg)
			.background_(colors.black)
			.font_(fVal)
			.clipLo_(min).clipHi_(max)
			.decimals_(2);

		sl = Slider(grp, Rect(labW + nbW + gap, 4, slw, rowH - 10));

		sl.action_({
			var vv;
			vv = fromSlider.(sl.value);
			nb.value_(vv);
			~harmoniumSetParam.(param, vv);
		});

		nb.action_({ |box|
			var vv;
			vv = box.value.clip(min, max);
			sl.value_(toSlider.(vv).clip(0, 1));
			~harmoniumSetParam.(param, vv);
		});

		v = init.clip(min, max);
		nb.value_(v);
		sl.value_(toSlider.(v).clip(0, 1));
		~harmoniumSetParam.(param, v);

		nextY = nextY + rowH;
	};

	// === MAIN WINDOW ===
	window = Window("Bearulator Harmonium v2.1", Rect(50, 50, wWidth, wHeight))
		.background_(colors.bg);

	// === LEFT PANEL: Controls ===
	ctrlScroll = ScrollView(window, Rect(8, 8, ctrlW, wHeight - 16))
		.hasVerticalScroller_(true)
		.hasHorizontalScroller_(false)
		.background_(colors.black);

	ctrlView = CompositeView(ctrlScroll, Rect(0, 0, ctrlW - 16, 1800))
		.background_(colors.black);

	// === RIGHT PANEL: Partial Grid ===
	gridScroll = ScrollView(window, Rect(ctrlW + 16, 8, wWidth - ctrlW - 24, wHeight - 16))
		.hasVerticalScroller_(true)
		.hasHorizontalScroller_(false)
		.background_(colors.black);

	gridView = CompositeView(gridScroll, Rect(0, 0, wWidth - ctrlW - 40, 400))
		.background_(colors.black);
	gridView.decorator = FlowLayout(gridView.bounds, 8@8, 4@4);

	// === TITLE ===
	StaticText(ctrlView, Rect(8, nextY, ctrlW - 16, 20))
		.string_("BEARULATOR HARMONIUM")
		.font_(Font("DejaVu Sans Mono", 14, true))
		.stringColor_(colors.cyan)
		.align_(\center);
	nextY = nextY + 22;

	StaticText(ctrlView, Rect(8, nextY, ctrlW - 16, 14))
		.string_("32-Band Filterbank Synthesis")
		.font_(fVal)
		.stringColor_(colors.fg.alpha_(0.6))
		.align_(\center);
	nextY = nextY + 22;

	// === SOURCE SELECTION ===
	StaticText(ctrlView, Rect(8, nextY, labW, 16))
		.string_("Source")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	srcMenu = PopUpMenu(ctrlView, Rect(labW + 14, nextY - 2, 180, 22))
		.background_(colors.brightBlack)
		.stringColor_(colors.fg)
		.items_(~harmoniumSources)
		.value_(~harmoniumParams[\srcSel] ? 1)
		.action_({ |m|
			~harmoniumSetParam.(\srcSel, m.value);
			updateVocoderVisibility.(m.value == 16);
		});
	nextY = nextY + rowH + 4;

	// === VOCODER MODE CONTROLS (visible when Source = 16) ===
	// Always reserve space so controls below don't overlap
	vocoderSection = CompositeView(ctrlView, Rect(8, nextY, ctrlW - 16, 95))
		.background_(colors.brightBlack.alpha_(0.5))
		.visible_(~harmoniumParams[\srcSel] == 16);

	StaticText(vocoderSection, Rect(4, 6, 200, 16))
		.string_("VOCODER MODE")
		.stringColor_(colors.magenta)
		.font_(Font("DejaVu Sans Mono", 10, true));

	StaticText(vocoderSection, Rect(4, 28, 80, 16))
		.string_("Track Input:")
		.stringColor_(colors.fg)
		.font_(fLbl);

	vocoderTrackMenu = PopUpMenu(vocoderSection, Rect(90, 26, 100, 22))
		.background_(colors.brightBlack)
		.stringColor_(colors.fg)
		.items_(["Track 1", "Track 2", "Track 3", "Track 4"])
		.value_(0);

	vocoderRouteBtn = Button(vocoderSection, Rect(200, 26, 80, 22))
		.states_([
			["START", colors.fg, colors.brightBlack],
			["ACTIVE", colors.black, colors.green]
		])
		.font_(Font("DejaVu Sans Mono", 9, true))
		.action_({ |btn|
			if(btn.value == 1, {
				// Initialize Harmonium input bus if needed
				~harmoniumInitBus.();

				// Hijack the selected track's output → Harmonium input
				if(~trackManager.notNil, {
					vocoderActiveTrack = vocoderTrackMenu.value;
					~trackManager.hijackTrackForVocoder(
						vocoderActiveTrack,
						~harmoniumInputBus.index
					);
					// Update inBus param so synth reads from correct bus
					~harmoniumSetParam.(\inBus, ~harmoniumInputBus.index);
				}, {
					"[Harmonium] Error: Track manager not available".warn;
					btn.value_(0);
				});
			}, {
				// Restore the hijacked track's routing
				if(~trackManager.notNil and: { vocoderActiveTrack.notNil }, {
					~trackManager.restoreTrackRouting(vocoderActiveTrack);
					vocoderActiveTrack = nil;
				});
			});
		});

	StaticText(vocoderSection, Rect(4, 58, 80, 16))
		.string_("Input Gain:")
		.stringColor_(colors.fg)
		.font_(fLbl);

	vocoderGainSlider = Slider(vocoderSection, Rect(90, 58, 140, 18))
		.value_(1.0)
		.action_({ |sl|
			~harmoniumSetParam.(\inGain, sl.value.linlin(0, 1, 0, 2));
		});

	NumberBox(vocoderSection, Rect(235, 56, 45, 20))
		.value_(1.0)
		.decimals_(2)
		.font_(fVal)
		.clipLo_(0).clipHi_(2)
		.action_({ |nb|
			vocoderGainSlider.value_(nb.value.linlin(0, 2, 0, 1));
			~harmoniumSetParam.(\inGain, nb.value);
		});

	// Function to show/hide vocoder controls
	updateVocoderVisibility = { |isVocoder|
		{ vocoderSection.visible_(isVocoder) }.defer;
	};

	// Always reserve space for vocoder section (100px)
	nextY = nextY + 100;

	// === FORMATION ===
	StaticText(ctrlView, Rect(8, nextY, labW, 16))
		.string_("Formation")
		.stringColor_(colors.fg)
		.font_(fLbl);
	PopUpMenu(ctrlView, Rect(labW + 14, nextY - 2, 180, 22))
		.background_(colors.brightBlack)
		.stringColor_(colors.fg)
		.items_(~harmoniumFormations)
		.value_(~harmoniumParams[\formation] ? 0)
		.action_({ |m| ~harmoniumSetParam.(\formation, m.value) });
	nextY = nextY + rowH;

	// === LPG MODE ===
	StaticText(ctrlView, Rect(8, nextY, labW, 16))
		.string_("LPG Mode")
		.stringColor_(colors.fg)
		.font_(fLbl);
	PopUpMenu(ctrlView, Rect(labW + 14, nextY - 2, 180, 22))
		.background_(colors.brightBlack)
		.stringColor_(colors.fg)
		.items_(~harmoniumLPGModes)
		.value_(~harmoniumParams[\lpgMode] ? 0)
		.action_({ |m| ~harmoniumSetParam.(\lpgMode, m.value) });
	nextY = nextY + rowH + 8;

	// === FILTERBANK ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("FILTERBANK")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	mkRow.("Num Partials", 1, 32, 32, 1, 0, \num);
	mkRow.("RQ (bandwidth)", 0.001, 0.2, 0.02, 0.001, 4, \rq);
	mkRow.("Rolloff", 0, 3, 1, 0.01, 2, \rolloff);
	mkRow.("Band Resonance", 0, 1, 0, 0.01, 2, \bandRes);
	mkRow.("Timbre", 0, 1, 0.5, 0.01, 2, \timbre);
	mkRow.("Pre-Saturation", 0, 6, 0, 0.01, 2, \preSat);

	CheckBox(ctrlView, Rect(8, nextY, 200, 18))
		.string_("Bypass Filterbank")
		.value_(~harmoniumParams[\bypassBPF] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\bypassBPF, cb.value) })
		.font_(fVal);
	nextY = nextY + rowH + 8;

	// === FM SECTION ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("FM MODULATION")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	CheckBox(ctrlView, Rect(8, nextY, 100, 18))
		.string_("FM Enable")
		.value_(~harmoniumParams[\fmEnable] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\fmEnable, cb.value) })
		.font_(fVal);
	CheckBox(ctrlView, Rect(128, nextY, 100, 18))
		.string_("FM Track")
		.value_(~harmoniumParams[\fmTrack] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\fmTrack, cb.value) })
		.font_(fVal);
	nextY = nextY + rowH;

	mkFreqRow.("FM Hz", 0.1, 20000, ~harmoniumParams[\fmHz] ? 100, \fmHz);
	mkRow.("FM Index", 0, 10, 0, 0.01, 2, \fmIndex);
	mkRow.("FM Mix", 0, 1, 0, 0.01, 2, \fmMix);
	mkRow.("FM Ratio Num", 1, 64, 1, 1, 0, \fmRatioNum);
	mkRow.("FM Ratio Den", 1, 64, 1, 1, 0, \fmRatioDen);

	// === RM SECTION ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("RING MODULATION")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	CheckBox(ctrlView, Rect(8, nextY, 100, 18))
		.string_("RM Enable")
		.value_(~harmoniumParams[\rmEnable] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\rmEnable, cb.value) })
		.font_(fVal);
	CheckBox(ctrlView, Rect(128, nextY, 100, 18))
		.string_("RM Track")
		.value_(~harmoniumParams[\rmTrack] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\rmTrack, cb.value) })
		.font_(fVal);
	nextY = nextY + rowH;

	mkFreqRow.("RM Hz", 0.1, 20000, ~harmoniumParams[\rmHz] ? 30, \rmHz);
	mkRow.("RM Depth", 0, 1, 0, 0.01, 2, \rmDepth);
	mkRow.("RM Ratio Num", 1, 64, 1, 1, 0, \rmRatioNum);
	mkRow.("RM Ratio Den", 1, 64, 1, 1, 0, \rmRatioDen);

	// === ENVELOPE ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("ENVELOPE (ADSR)")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	mkRow.("Attack", 0.001, 2.0, 0.005, 0.001, 3, \envAtk);
	mkRow.("Decay", 0.001, 2.0, 0.15, 0.001, 3, \envDec);
	mkRow.("Sustain", 0, 1, 0.7, 0.01, 2, \envSus);
	mkRow.("Release", 0.001, 5.0, 0.25, 0.001, 3, \envRel);

	// === SWIRL ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("SWIRL (Stereo Animation)")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	CheckBox(ctrlView, Rect(8, nextY, 120, 18))
		.string_("Swirl Enable")
		.value_(~harmoniumParams[\swirlOn] ? 1)
		.action_({ |cb| ~harmoniumSetParam.(\swirlOn, cb.value) })
		.font_(fVal);
	nextY = nextY + rowH;

	mkRow.("Swirl Rate", 0.001, 1.0, 0.03, 0.001, 3, \swirlRate);
	mkRow.("Swirl Depth", 0, 1, 0.3, 0.01, 2, \swirlDepth);

	// === SMJ ===
	CheckBox(ctrlView, Rect(8, nextY, 180, 18))
		.string_("SMJ (Staggered Attack)")
		.value_(~harmoniumParams[\smjEnable] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\smjEnable, cb.value) })
		.font_(fVal);
	nextY = nextY + rowH;

	mkRow.("SMJ Max (s)", 0, 8, 2, 0.1, 1, \smjMax);

	// === SUB OSCILLATORS ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("SUB OSCILLATORS")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	mkRow.("Sub Amp", 0, 1, 0, 0.01, 2, \subAmp);

	CheckBox(ctrlView, Rect(8, nextY, 120, 18))
		.string_("Sub -1 Oct")
		.value_(~harmoniumParams[\subOct1] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\subOct1, cb.value) })
		.font_(fVal);
	CheckBox(ctrlView, Rect(138, nextY, 120, 18))
		.string_("Sub -2 Oct")
		.value_(~harmoniumParams[\subOct2] ? 0)
		.action_({ |cb| ~harmoniumSetParam.(\subOct2, cb.value) })
		.font_(fVal);
	nextY = nextY + rowH + 8;

	// === OUTPUT ===
	StaticText(ctrlView, Rect(8, nextY, 200, 16))
		.string_("OUTPUT")
		.stringColor_(colors.yellow)
		.font_(Font("DejaVu Sans Mono", 10, true));
	nextY = nextY + 20;

	mkFreqRow.("Fund Hz", 20, 2000, ~harmoniumParams[\fund] ? 220, \fund);
	mkRow.("Makeup Gain", 0.2, 40, 3, 0.1, 1, \makeup);
	mkRow.("LPF Hz", 20, 20000, 14000, 1, 0, \lpfHz);
	mkRow.("Wet", 0, 1, 1, 0.01, 2, \wet);
	mkRow.("Amp", 0, 1, 0.5, 0.01, 2, \amp);

	// === PARTIAL GRID ===
	StaticText(gridView, Rect(0, 0, 700, 20))
		.string_("PARTIAL GRID (Mask + Gain)")
		.font_(Font("DejaVu Sans Mono", 11, true))
		.stringColor_(colors.yellow);

	// Create 32 slider+button combos
	sliders = Array.fill(maxPartials, { nil });
	buttons = Array.fill(maxPartials, { nil });

	maxPartials.do({ |i|
		var comp, sl, b;
		comp = CompositeView(gridView, Rect(0, 0, btnW, slH + btnH + 4));

		sl = Slider(comp, Rect((btnW - slW) / 2, 2, slW, slH - 4))
			.orientation_(\vertical)
			.value_(gainArray[i])
			.action_({ |sld| setGainAt.(i, sld.value) });
		sliders[i] = sl;

		b = Button(comp, Rect(0, slH + 4, btnW, btnH))
			.states_([
				[(i + 1).asString, colors.fg, colors.brightBlack],
				[(i + 1).asString, colors.black, colors.cyan]
			])
			.value_(maskArray[i])
			.font_(Font("DejaVu Sans Mono", 8))
			.action_({ |but| setMaskAt.(i, but.value) });
		buttons[i] = b;
	});

	// Spacer
	CompositeView(gridView, Rect(0, 0, gridView.bounds.width - 40, 1));

	// Preset buttons
	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["All On", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			setAllMasks.(1);
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["All Off", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			setAllMasks.(0);
			maskArray[0] = 1;
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["Primes", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			var primes;
			primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31];
			setAllMasks.(0);
			maskArray[0] = 1;
			primes.do({ |p| if(p <= maxPartials, { maskArray[p - 1] = 1 }) });
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["Odds", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			setAllMasks.(0);
			maxPartials.do({ |i| if(((i + 1) % 2) == 1, { maskArray[i] = 1 }) });
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["Evens", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			setAllMasks.(0);
			maskArray[0] = 1;
			maxPartials.do({ |i| if(((i + 1) % 2) == 0, { maskArray[i] = 1 }) });
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["Octaves", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			setAllMasks.(0);
			[1, 2, 4, 8, 16, 32].do({ |h| if(h <= maxPartials, { maskArray[h - 1] = 1 }) });
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	Button(gridView, Rect(0, 0, 60, 22))
		.states_([["First 16", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({
			setAllMasks.(0);
			16.do({ |i| maskArray[i] = 1 });
			~harmoniumSetParam.(\mask, maskArray);
			refreshButtons.(buttons);
		});

	// Another spacer
	CompositeView(gridView, Rect(0, 0, gridView.bounds.width - 40, 8));

	// === KEYBOARD HINT ===
	StaticText(gridView, Rect(0, 0, 700, 18))
		.string_("Keyboard: A-L = notes, Z/X = octave, ESC = panic | MIDI: Auto-enabled when window open")
		.font_(fVal)
		.stringColor_(colors.fg.alpha_(0.6));

	// Test button
	Button(gridView, Rect(0, 0, 80, 22))
		.states_([["TEST TONE", colors.fg, colors.brightBlack]])
		.font_(fVal)
		.action_({ ~harmoniumTest.() });

	// === KEYBOARD INPUT ===
	window.view.keyDownAction_({ |view, char, mod, unicode, keycode|
		var noteMap, note, newFund;
		noteMap = (
			$a: 0, $w: 1, $s: 2, $e: 3, $d: 4, $f: 5, $t: 6,
			$g: 7, $y: 8, $h: 9, $u: 10, $j: 11, $k: 12, $l: 14
		);

		// ESC = panic
		if(unicode == 27, { ~harmoniumPanic.() });

		// Octave shift
		if(char == $z, {
			newFund = (~harmoniumParams[\fund] / 2).max(20);
			~harmoniumSetParam.(\fund, newFund);
			("[Harmonium] Fund: " ++ newFund.round(0.01) ++ " Hz").postln;
		});

		if(char == $x, {
			newFund = (~harmoniumParams[\fund] * 2).min(2000);
			~harmoniumSetParam.(\fund, newFund);
			("[Harmonium] Fund: " ++ newFund.round(0.01) ++ " Hz").postln;
		});

		note = noteMap[char.toLower];
		if(note.notNil, {
			~harmoniumNoteOn.(60 + note, 100, 0);
		});
	});

	window.view.keyUpAction_({ |view, char, mod, unicode, keycode|
		var noteMap, note;
		noteMap = (
			$a: 0, $w: 1, $s: 2, $e: 3, $d: 4, $f: 5, $t: 6,
			$g: 7, $y: 8, $h: 9, $u: 10, $j: 11, $k: 12, $l: 14
		);
		note = noteMap[char.toLower];
		if(note.notNil, {
			~harmoniumNoteOff.(60 + note, 0);
		});
	});

	// === CLEANUP ===
	window.onClose_({
		~harmoniumPanic.();

		// Disable MIDI routing to Harmonium
		~harmoniumDisableMIDI.();

		// Restore any hijacked track routing
		if(~trackManager.notNil and: { vocoderActiveTrack.notNil }, {
			~trackManager.restoreTrackRouting(vocoderActiveTrack);
			vocoderActiveTrack = nil;
			"[Harmonium] Track routing restored on window close.".postln;
		});

		"[Harmonium] GUI closed.".postln;
	});

	// Enable MIDI when window opens
	~harmoniumEnableMIDI.();

	window.front;
	window;
};

"[Harmonium GUI v2.1] Interface loaded.".postln;
"  - Open with: ~makeHarmoniumGUI.()".postln;
"  - Keyboard: A-L = notes, Z/X = octave, ESC = panic".postln;
"  - Vocoder: Set Source to 16 (TRACK AUDIO), select track, press START".postln;
