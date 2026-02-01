# Harmonium → Bearulator Connection Issue

**Problem:** The new Harmonium section (32-band filterbank additive synth) is not connecting properly to the Bearulator grain engine.

**Status:** Analyzed 2026-02-01

---

## Understanding the Architecture

### What Harmonium Does
- 32-band additive synthesis filterbank (inspired by Trevor Treglia's Harmonium)
- Can run in two modes:
  1. **Standalone:** Self-contained synth, triggered via MIDI
  2. **Vocoder Mode:** Receives audio from Bearulator's grain tracks, shapes it via 32-band EQ

### The Connection Path
When in Vocoder Mode, the signal flow should be:
```
Track 1 Grain Synth → Harmonium Input Bus → Harmonium 32-Band Filter → Output
```

The function that handles this hijack:
- `~harmoniumStartRouting(trackNum)` in `harmonium-engine.scd`
- Calls `~trackManager.hijackTrackForVocoder(trackNum, harmBus.index)`
- This redirects `track.grainSynth.set(\out, destinationBus, ...)`

---

## Theory: Why It's Probably Broken

### Theory 1: **Synth Not Created Yet** ⭐ MOST LIKELY
The hijack function assumes `track.grainSynth` exists. But:
- `track.grainSynth` is created by `~trackManager.startPlayback(trackNum)` in track-manager.scd (line 217)
- If you call `~harmoniumStartRouting()` before loading a sample/starting grain synthesis, the synth is `nil`
- When hijack tries `track.grainSynth.set(...)` on a nil object, it silently fails

**Fix:** Load a sample and start the grain synth on Track 1 BEFORE calling harmonium vocoder mode.

**Check:** `~trackManager.tracks[0].grainSynth` should not be nil

---

### Theory 2: **Bus Index Mismatch**
The vocoder mode reads from `~harmoniumInputBus`. But:
- `~harmoniumInitBus` creates a stereo bus: `Bus.audio(Server.default, 2)`
- The hijack redirects the synth to that bus
- Then `harmonium-engine.scd` reads from it with `In.ar(inBus, 2)` (line 223)
- Issue: If the bus index is wrong, or gets freed/reallocated, the read will get silence

**Check:** 
```supercollider
~harmoniumInputBus.index  // Should be a consistent positive number (e.g., 8, 10)
~harmoniumParams[\inBus]  // Should match the above
```

---

### Theory 3: **Group/Synth Ordering Issue**
SuperCollider requires careful synth ordering:
- Source synth (Track 1 grain) must write to bus BEFORE reader synth (Harmonium) reads from it
- If Harmonium synth was created BEFORE the hijack, it might be reading before the grain synth writes

**Check:**
```supercollider
s.queryAllNodes  // Show synth tree - Harmonium should come AFTER Track 1
```

---

### Theory 4: **Array Parameters Not Passed**
In the Harmonium init code (harmonium-engine.scd line ~490), there's a note:
```supercollider
// Arrays (mask, gains) must be passed via setn after synth creation
```

If the mask or gains arrays are empty or not properly initialized, the harmonium won't pass audio through.

**Check:**
```supercollider
~harmoniumParams[\mask]   // Should be [1,1,1,... 1,1] (32 elements)
~harmoniumParams[\gains]  // Should be Array.fill(32, 1.0)
```

---

### Theory 5: **No Harmonium Synth Actually Exists**
The vocoder reads from `inBus`, but if no Harmonium synth (`\bearulatorHarmonium`) was ever spawned, there's nothing reading that bus.

**Check:**
```supercollider
~harmoniumVoices  // Should not be empty if synth is playing
~harmoniumParams  // Should be initialized
```

---

## Debugging Checklist

1. **Load a sample first:**
   ```supercollider
   ~trackManager.loadSample(0, "~/Documents/supercollider/granular/samples/yourfile.wav");
   ~trackManager.startPlayback(0);
   ```

2. **Check Track 1 grain synth exists:**
   ```supercollider
   ~trackManager.tracks[0].grainSynth  // Should be a Synth, not nil
   ```

3. **Manually route to Harmonium:**
   ```supercollider
   ~harmoniumStartRouting(0)  // Route Track 1 to Harmonium vocoder
   ```

4. **Check vocoder input bus is wired:**
   ```supercollider
   ~harmoniumInputBus.index     // Get bus number
   ~harmoniumParams[\inBus]     // Should match above
   ```

5. **Spawn a Harmonium synth:**
   ```supercollider
   ~harmoniumNoteOn(60, 100);  // Play C4 (MIDI 60)
   ```

6. **Check synth tree:**
   ```supercollider
   s.queryAllNodes;  // Visualize order
   ```

7. **Monitor input bus:**
   ```supercollider
   ~harmoniumInputBus.scope;  // Scope the vocoder input - should see waveform
   ```

---

## Likely Root Cause

**Most probable:** The Harmonium synth and/or Track grain synth haven't been initialized when the hijack is called. The connection code exists and is probably correct, but it's trying to route `nil` to `nil`.

**Quick fix:**
1. Load a sample on Track 1
2. Click "Play" to start the grain synth
3. THEN enable vocoder mode (if there's a button)
4. THEN spawn a Harmonium voice

---

## Code Locations

- **Harmonium engine:** `core/harmonium-engine.scd` (lines 380-430 for routing)
- **Track manager hijack:** `core/track-manager.scd` (lines 579-625)
- **Grain synth creation:** `core/track-manager.scd` (line 217)
- **Harmonium synth spawn:** `core/harmonium-engine.scd` (line ~490)

---

## Next Steps

Run the debugging checklist above and report:
1. What value does `~trackManager.tracks[0].grainSynth` return?
2. What's in `s.queryAllNodes` output?
3. Does `~harmoniumInputBus.scope` show audio when Track 1 is playing?
