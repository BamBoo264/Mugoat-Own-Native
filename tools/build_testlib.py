from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
files=[r/'Core/Inflate.c']+sorted((r/'Vendor/zstd/lib/common').glob('*.c'))+sorted((r/'Vendor/zstd/lib/decompress').glob('*.c'))
objects=[]
for i,source in enumerate(files):
 target=out/(str(i)+'.o');args=['clang','-O1','-DZSTD_DISABLE_ASM','-c',str(source),'-o',str(target)]
 if '--sanitize' in sys.argv:args.insert(1,'-fsanitize=address')
 subprocess.run(args,check=True);objects.append(str(target))
subprocess.run(['ar','rcs',str(out/'runtime.a')]+objects,check=True)
