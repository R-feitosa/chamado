# Trilha do vídeo Feitosa Imóveis: música (vol-12, ~110 BPM) + acentos suaves nos cliques e cortes.
import subprocess, os, sys
A, OUT = sys.argv[1], sys.argv[2]
DUR = 22
ev = [(0.1, 'impact/impactSoft_medium_001.ogg', 0.7), (3.27, 'impact/impactSoft_medium_004.ogg', 0.4),
      (17.3, 'interface/bong_001.ogg', 0.45), (18.56, 'impact/impactSoft_heavy_002.ogg', 0.55), (18.62, 'impact/impactBell_heavy_003.ogg', 0.25)]
ev += [(c, 'interface/click_003.ogg', 0.5) for c in [5.3, 8.4, 12.5, 13.5, 14.5, 15.5, 16.3, 17.1]]
ins = ['-i', os.path.join(A, 'music', 'happy-beats-business-moves-vol-12-by-ende-dot-app.mp3')]; fl = []
for i, (t, f, v) in enumerate(ev):
    ins += ['-i', os.path.join(A, 'sfx', f)]; d = int(t * 1000)
    fl.append(f'[{i+1}:a]aformat=sample_rates=48000:channel_layouts=stereo,volume={v},adelay={d}|{d}[s{i}]')
fl.append(''.join(f'[s{i}]' for i in range(len(ev))) + f'amix=inputs={len(ev)}:normalize=0,highshelf=f=6000:g=-4,aecho=0.8:0.5:60|110:0.15|0.08[sfx]')
fl.append(f'[0:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:{DUR},volume=0.6,afade=t=in:d=0.2,afade=t=out:st={DUR-1.6}:d=1.6[mus]')
fl.append(f'[mus][sfx]amix=inputs=2:normalize=0,alimiter=limit=0.9,apad=whole_dur={DUR},atrim=0:{DUR},loudnorm=I=-16:TP=-1.5:LRA=11[out]')
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *ins, '-filter_complex', ';'.join(fl), '-map', '[out]', '-ar', '48000', '-c:a', 'pcm_s16le', OUT], check=True)
