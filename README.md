# Odin Game of Live 
Example of Game of Live using `odin` and the awesome [sokol library](https://github.com/floooh/sokol-odin).


## Prerequisites 
Make sure you have [Odin](https://odin-lang.org/) installed. Next you have to compile the Sokol libraries for your operating system. For that just execute the build scripts (depending on your operating system)

```bash
cd src/sokol
./build_clibs_macos.sh # Compiling Sokol Libs for MacOS
./build_clibs_linux.sh # Compiling Sokol Libs for Linux 
./build_clibs_windows.cmd # Compiling Sokol Libs for Windows 
```

## Running 
With the prerequisites in place it should be as simple as running

```bash
odin run src/
```

