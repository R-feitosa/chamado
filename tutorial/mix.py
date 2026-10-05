# Trilha do tutorial: música baixa + cliques e digitação suaves nos tempos do roteiro (gravar.cjs).
import subprocess, os
D = os.path.dirname(os.path.abspath(__file__))
A = os.path.join(D, '..', '.agents', 'skills', 'brag', 'assets')
DUR = 86
CLIQUES = [13.4, 14.7, 16.8, 27.9, 31.3, 36.6, 42.7, 44.7, 47.0, 49.8, 55.8, 65.1, 66.3, 67.8, 73.4, 75.2, 76.2, 77.4]
DIGITA = [(14.8, 15.9, 9), (16.9, 17.8, 8), (31.4, 35.4, 104), (66.4, 67.0, 3)]
ev = [(0.2, 'impact/impactSoft_medium_001.ogg', 0.6), (5.0, 'impact/impactSoft_medium_004.ogg', 0.45), (81.0, 'impact/impactSoft_medium_002.ogg', 0.5),
      (56.0, 'interface/bong_001.ogg', 0.35), (77.6, 'interface/bong_001.ogg', 0.35)]
ev += [(c, 'interface/click_003.ogg', 0.5) for c in CLIQUES]
for a, b, n in DIGITA:  # um toque a cada ~3 letras, bem baixo
    passos = max(1, n // 3)
    ev += [(a + (b - a) * i / passos, f'keyboard/keypress-{(i % 12) + 1:03d}.wav', 0.1) for i in range(passos)]
ins = ['-i', os.path.join(A, 'music', 'happy-beats-business-moves-vol-9-by-ende-dot-app.mp3')]
fl = []
for i, (t, f, v) in enumerate(ev):
    ins += ['-i', os.path.join(A, 'sfx', f)]
    d = int(t * 1000)
    fl.append(f'[{i+1}:a]aformat=sample_rates=48000:channel_layouts=stereo,volume={v},adelay={d}|{d}[s{i}]')
fl.append(''.join(f'[s{i}]' for i in range(len(ev))) + f'amix=inputs={len(ev)}:normalize=0,highshelf=f=6000:g=-4[sfx]')
fl.append(f'[0:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:{DUR},volume=0.3,afade=t=in:d=0.6,afade=t=out:st={DUR-3}:d=3[mus]')
fl.append(f'[mus][sfx]amix=inputs=2:normalize=0,alimiter=limit=0.9,apad=whole_dur={DUR},atrim=0:{DUR},loudnorm=I=-18:TP=-1.5:LRA=11[out]')
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *ins, '-filter_complex', ';'.join(fl), '-map', '[out]', '-ar', '48000', '-c:a', 'pcm_s16le', os.path.join(D, 'work', 'trilha.wav')], check=True)
