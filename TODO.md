# BEARULATOR: Master TODO List

# DAT Feb 8 TROUBLESHOOTING

- [x] Harmonium. When source is set to TRACK AUDIO (Vocoder), all sound STOPS when i press START. **FIXED:** Variable name mismatch (`track.directSynth` → `track.directPlaybackSynth`) caused Direct engine to not be redirected while master bus was muted.
- [x] Keystep: Connect button should be clustered together with SYNC Manager and Keystep MIDI track selector in the GUI's Main/Master section. **FIXED:** Moved from line 1392 to line 820, now directly between BPM controls and track selectors.
- [x] TAP Tempo: Button does not change numerical value in BPM box. **FIXED:** Added setMainBpmBox() method to sync-manager and registered main window BPM box for updates.
- [ ] SYNC Manager: Clarity and Control. Needs discussion. Current behavior of randomized hits and loosely controlled tempos is unexpected; desired behavior is tighter, more predictable tempo and synchronization, similar to a drum machine.
- [ ] RESET PARAMS Function: Continue testing and work on fixing its inconsistent behavior; it has never worked 100%.
- [ ] Waveform Display / Granular Position: The graphical representation of granular position is inaccurate when a loop is selected. Request: Limit granular position graphic to the looped selection, zoom waveform to the loop size upon selection, and allow easy zoom-out/new selection by clicking and dragging.

**Current Version:** v2.2 (January 2026)

---

## 🎯 **Immediate Priorities: The v2.1 Engine Deployment**

### 1. Deploy v2.1 Engine
**Status:** **High Priority.** The current v2.0 engine has critical audio bugs.
**Action:** Overwrite the contents of `core/grain-engine.scd` with the v2.1 code stored in `bearulator_project_state.org`.
**Verification:**
- Run the "Deploy Script" from `bearulator_project_state.org`.
- Confirm that switching filters and modes no longer causes audio glitches.
- Verify `timeStretch` at 0.0 freezes audio without a pitch drop.
- Verify `pitchSeq` accepts 64-step arrays.

### 2. Create "Sigur Ros" Preset
**Status:** Pending v2.1 deployment.
**Objective:** Create a generative ambient preset rivaling "1-5fq".
**Recipe:**
- **Sample:** Pure Rhodes, Chime, or Female Vocal.
- **Settings:** `timeStretch` = 0.1, `reverbMix` = 0.7, `shimmerMix` = 0.5.
- **Sequencer:** 64-step slow drift on a Pentatonic scale.

### 3. Implement `DiskOut` for Recording
**Status:** Pending v2.1 deployment.
**Task:** Implement `DiskOut` in the engine to record the output directly to a WAV file, building a sample library.



## 🔬 **Research & Cross-Pollination**

### Harmonium Evaluation & Cannibalizing
**Status:** Scheduled evaluation.
**Objective:** Study Trevor Treglia's Harmonium synth and identify valuable patterns/components for Bearulator.
**Reference Files:**
- `~/Documents/supercollider/harmonium.scd` (main synth)
- `~/Documents/supercollider/harmonium_analysis.md` (component breakdown)
**Key Areas to Evaluate:**
- Additive synthesis partials grid (vs. Bearulator's granular approach)
- Voice stealing & MIDI polyphony management (solid implementation)
- Krell-inspired generative arpeggiator (potential inspiration)
- Spectral shaping via manual parameter arrays
- Ring mod & FM implementation
- Buchla-style LPG (Low Pass Gate) with vactrol emulation
- Recording system with timestamped filenames
**Potential Cannibalizations:**
- Voice stealing logic for Bearulator's poly engine
- Generative arpeggiator for performance macro system
- Spectral shaping concepts for synth design
- LPG topology for creative filter morphing
**Note:** Harmonium is additive (bottom-up); Bearulator is granular (top-down). Value will be in specific techniques, not architecture.

---

## 🚀 **Future Enhancements & 2026 Roadmap**

### Core Engine & Sound Design
- **[ ] Install "Mi-UGens":** Replace the filterbank with `MiRings` for physical modeling resonance.
- **[ ] Install "Greyhole":** Replace `FreeVerb` with Greyhole for "Blackhole" style spaces.
- **[ ] Implement "Spectral Split":** Use `PV_HainsworthFoote` or `FluidHPSS` to route transients away from reverb.
- **[ ] Implement "Barberpole" Phaser:** Use `FreqShift` for infinite rising/falling spectral sweeps.
- **[ ] Upgrade Filter to "Acid" Topology:** Use `VADDiodeFilter` (TB-303 style) for squelchy resonance.
- **[ ] Add "Squiz" Artifacts:** Use the `Squiz` UGen for aliasing/downsampling IDM textures.
- **[ ] Spectral Photobooth:** A feature to capture and manipulate spectral frames.

### System & UI
- **[ ] Shared Clock & Phase Lock:** A system to sync all four tracks.
- **[ ] Preset Management GUI:** A visual browser for managing presets.
- **[ ] Track Naming System:** Allow users to name their tracks.
- **[ ] Neon Glow Rendering:** Implement hardware-accelerated "glow" visuals.
- **[ ] Quad Panner: Add 'motion' options (e.g., Circular, Random) with reference to `examples/quad-spatial-examples.scd` for inspiration.
- **[ ] Comprehensive Recording Function:** Implement a function to record speaker output (including MOTU inputs) to WAV files in `samples/recordings`, with selectable input sources.

### Project Health & Workflow Enhancements
- **[ ] Addressing Existing Issues:** Review `COMMON-BUGS.md` and `TODO.md` to prioritize and resolve known bugs and pending tasks. Investigate the purpose of `fix-spectral-safe.scd` and `fix-spectral.scd` to ensure spectral issues are fully resolved.
- **[ ] Feature Enhancement/Refinement:** Go through `IMPROVEMENT-SUGGESTIONS.md` to identify and implement valuable new features or enhancements. Consider areas where the granular engine's interaction might be confusing (like the `timeStretch` / `scanSpeed` example) and improve documentation or UI feedback.
- **[ ] Testing and Stabilization:** Ensure comprehensive testing, especially for recent changes related to `v2.4`. Following the `TESTING-GUIDE.md` to create or update test scripts for any modifications we make. Verify the stability of the `sc3-plugins` dependency.
- **[ ] Codebase Understanding and Documentation:** Continue to use `main.scd` and `track-manager.scd` as primary guides for understanding the system's flow. Potentially update `gemini.md` or other relevant documentation with specific operational details for parameters like `timeStretch` in the granular engine to prevent future confusion.

---

## 🧹 **Technical Debt & Known Issues**

- **[ ] Remove Deprecated Parameters:** Clean up unused filter parameters in `grain-engine.scd`.
- **[ ] Centralize Hardcoded Values:** Refactor filter ranges, update rates, etc., into a central location.
- **[ ] Remove Unused Variables:** Remove the `phaseBus` variable from `track-manager.scd`.
- **[ ] Inefficient Waveform Display:** The waveform display uses temporary files for recorded buffers, which is functional but inefficient.
- **[ ] GUI Layout Cleanup:** Some GUI elements overlap in the Master tab and need tidying.

---
## 🐛 **ACTIVE BUGS & DIAGNOSTICS**

### Harmonium → Bearulator Connection Issue
**Status:** Diagnosed 2026-02-01
**Problem:** New Harmonium additive synth section not properly connecting to grain engine in vocoder mode
**See:** HARMONIUM-DIAGNOSIS.md for full analysis and debugging checklist
**Most Likely Cause:** Grain synth not initialized before hijack attempted
**Quick Test:**
```supercollider
~trackManager.tracks[0].grainSynth  // Should not be nil
~harmoniumInputBus.scope            // Should show audio from Track 1
```

---

**Last Updated:** 2026-02-01
