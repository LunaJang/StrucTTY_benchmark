srun -w super001 --ntasks=1 --cpus-per-task=1 --mem=8G --pty bash

cd ~/src/StrucTTY_benchmark/benchmark_results
ulimit -v 4194304
for f in ~/src/StrucTTY_benchmark/benchmark/*.cif; do
    for i in $(seq 1 5); do
        taskset -c 0 ~/src/StrucTTY/build/StrucTTY "$f" -b
    done
done