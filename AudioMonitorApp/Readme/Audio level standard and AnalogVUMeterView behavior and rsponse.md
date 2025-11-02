#  Audio levels, standard and response
![Test](https://via.placeholder.com/150)

The audio levels follow a digital *dBFS* (decibels relative to full scale) standard — the common digital-audio reference used by macOS, iOS, and DAWs
 The Standard uses DBFS:  DBFS(decibels full scale) measures amplitude relative to the symtem's maximum possible digital value(0 dBFS).
 
 0 dBFS = maximum digtal peak(clipping point, no valid digital signal can exceed this. A typical analog reference or “nominal” digital operating level is between –18 dBFS and –12 dBFS (depending on calibration).
 
 -6 dB  → strong signal, still safe
 -18 dB → nominal level
 -60 dB → very quiet
 -120 dB → effectively silence (noise floor)
 
 AudioManager calculates instantaneous RMS or peak levels from the audio buffer using this formula (simplified):
 
 let rms = sqrt(sum(samples^2) / N)
 let db = 20 * log10(rms)

 Producing vaes in dBFS because samples are normalized floating-point values(-10 to +1.0).
 
 •    1.0 → 0 dBFS
 •    0.5 → about –6 dBFS
 •    0.1 → about –20 dBFS
 
 The analog VU meter uses (VU(Volume Units), where 0VU is about -18 dBFS digital.
 Simulate analog behavior by applying exponential smoothing to your smoothedLeft / smoothedRight updates.
 smoothedLeft = smoothedLeft * 0.9 + newValue * 0.1
 
![Audio standards summary](Documentation/Standards_used_Summary.png)
<img src="Documentation/Standards_used_Summary.png" width="400" alt="Audio standards usage summary">

