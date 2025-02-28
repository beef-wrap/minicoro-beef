mkdir libs

copy minicoro\minicoro.h minicoro\minicoro.c

clang -c -g -gcodeview -o minicorod.lib -target x86_64-pc-windows -fuse-ld=llvm-lib -Wall -DMINICORO_IMPL minicoro\minicoro.c
move minicorod.lib libs

clang -c -O3 -o minicoro.lib -target x86_64-pc-windows -fuse-ld=llvm-lib -Wall -DMINICORO_IMPL minicoro\minicoro.c
move minicoro.lib libs

del minicoro\minicoro.c