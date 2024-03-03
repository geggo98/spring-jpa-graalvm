{
   description = "GraalVM Oracle Closed Source (fomerly called Enterprise Edition) 21.0.2";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs";
        # See https://www.oracle.com/java/technologies/javase/graalvm-jdk21-archive-downloads.html
        # for the latest links and the corresponding SHA256 hashes.
        # License: https://www.oracle.com/downloads/licenses/graal-free-license.html
        graalvmX8664Linux = {
            url = "https://download.oracle.com/graalvm/21/archive/graalvm-jdk-21.0.2_linux-x64_bin.tar.gz";
            flake = false;
        };
        graalvmAarch64Linux = {
            url = "https://download.oracle.com/graalvm/21/archive/graalvm-jdk-21.0.2_linux-aarch64_bin.tar.gz";
            flake = false;
        };
        graalvmAarch64Darwin = {
            url = "https://download.oracle.com/graalvm/21/archive/graalvm-jdk-21.0.2_macos-aarch64_bin.tar.gz";
            flake = false;
        };
        graalvmX8664Darwin = {
            url = "https://download.oracle.com/graalvm/21/archive/graalvm-jdk-21.0.2_macos-x64_bin.tar.gz";
            flake = false;
        };
    };

   outputs = { self, nixpkgs, graalvmX8664Linux, graalvmAarch64Linux, graalvmAarch64Darwin, graalvmX8664Darwin }: let
     lib = nixpkgs.lib;

     graalvm-oracle-ee = { system ? "x86_64-linux", src, extraCLibs ? [ ], gtkSupport ? (system == "x86_64-linux" || system == "aarch64-linux"), useMusl ? false, ... } @ args:
       # See also: https://github.com/NixOS/nixpkgs/blob/46b75bf589a56d67f5d2e00e6cda406d8c69d29d/pkgs/development/compilers/graalvm/community-edition/buildGraalvm.nix
       assert useMusl -> (system == "x86_64-linux" || system == "aarch64-linux");
       let
         pkgs = nixpkgs.legacyPackages.${system};
         extraArgs = builtins.removeAttrs args [
           "lib"
           "stdenv"
           "alsa-lib"
           "autoPatchelfHook"
           "cairo"
           "cups"
           "darwin"
           "fontconfig"
           "glib"
           "glibc"
           "gtk3"
           "makeWrapper"
           "musl"
           "runCommandCC"
           "setJavaClassPath"
           "unzip"
           "xorg"
           "zlib"
           "extraCLibs"
           "gtkSupport"
           "useMusl"
           "passthru"
           "meta"
         ];

         cLibs = lib.optionals (system == "x86_64-linux" || system == "aarch64-linux") (
           [ pkgs.glibc pkgs.zlib.static ]
           ++ lib.optionals (!useMusl) [ pkgs.glibc.static ]
           ++ lib.optionals useMusl [ pkgs.musl ]
           ++ extraCLibs
         );

         musl-gcc = (pkgs.runCommandCC "musl-gcc" { } ''
           mkdir -p $out/bin
           ln -s ${lib.getDev pkgs.musl}/bin/musl-gcc $out/bin/${pkgs.stdenv.hostPlatform.system}-musl-gcc
         '');
         binPath = lib.makeBinPath (lib.optionals useMusl [ musl-gcc ] ++ [ pkgs.stdenv.cc ]);

         runtimeLibraryPath = lib.makeLibraryPath
           ([ pkgs.cups ] ++ lib.optionals gtkSupport [ pkgs.cairo pkgs.glib pkgs.gtk3 ]);

         graalvm-oracle-ee = pkgs.stdenv.mkDerivation ({
           inherit src;
           # name = "graalvm-oracle-ee-21.0.2";
           pname = "graalvm-oracle-ee";
           version = "21.0.2";

           # dontUnpack = true;

           unpackPhase = ''
             runHook preUnpack

             mkdir -p "$out"

             (cd "$src${if (system == "x86_64-linux" || system == "aarch64-linux") then "" else "/Contents/Home/"}" && cp -a . "$out")
             # find "$out" -type l -exec sh -c 'target=$(readlink "{}"); rm "{}" && cp -a "$target" "{}"' \;

             if [ ! -d "$out/bin" ]; then
               ls $out
               echo "The 'bin' directory is missing after extracting the graalvm"
               echo "tarball, please compare the directory structure of the"
               echo "tarball with what happens in the unpackPhase."
               exit 1
             fi

             chmod u+w $out $out/bin
             mkdir -p $out/nix-support

             runHook postUnpack
           '';

           dontStrip = true;

           nativeBuildInputs = [ pkgs.unzip pkgs.makeWrapper ]
             ++ lib.optional (system == "x86_64-linux" || system == "aarch64-linux") pkgs.autoPatchelfHook;

           propagatedBuildInputs = [ pkgs.setJavaClassPath pkgs.zlib ]
             ++ lib.optional (system == "x86_64-darwin" || system == "aarch64-darwin") pkgs.darwin.apple_sdk.frameworks.Foundation;

           buildInputs = lib.optionals (system == "x86_64-linux" || system == "aarch64-linux") [
             pkgs.alsa-lib
             pkgs.fontconfig
             pkgs.stdenv.cc.cc.lib
             pkgs.xorg.libX11
             pkgs.xorg.libXext
             pkgs.xorg.libXi
             pkgs.xorg.libXrender
             pkgs.xorg.libXtst
           ];

           postInstall = ''
             ln -sf $out/include/linux/*_md.h $out/include/

             mkdir -p $out/nix-support
             cat > $out/nix-support/setup-hook << EOF
             if [ -z "\''${JAVA_HOME-}" ]; then export JAVA_HOME=$out; fi
             if [ -z "\''${GRAALVM_HOME-}" ]; then export GRAALVM_HOME=$out; fi
             EOF

             wrapProgram $out/bin/native-image \
               --prefix PATH : ${binPath} \
               ${toString (map (l: "--add-flags '-H:CLibraryPath=${l}/lib'") cLibs)}
           '';

           preFixup = lib.optionalString ((system == "x86_64-linux" || system == "aarch64-linux")) ''
             for bin in $(find "$out/bin" -executable -type f); do
               wrapProgram "$bin" --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}"
             done
           '';

           doInstallCheck = true;
           installCheckPhase = ''
             runHook preInstallCheck

             ${# broken in darwin
             lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") ''
               echo "Testing Jshell"
               echo '1 + 1' | $out/bin/jshell
             ''}

             echo ${lib.escapeShellArg ''
               public class HelloWorld {
                 public static void main(String[] args) {
                   System.out.println("Hello World");
                 }
               }
             ''} > HelloWorld.java
             $out/bin/javac HelloWorld.java

             echo "Testing GraalVM"
             $out/bin/java -XX:+UnlockExperimentalVMOptions -XX:+EnableJVMCI -XX:+UseJVMCICompiler HelloWorld | fgrep 'Hello World'

             export NATIVE_IMAGE_DEPRECATED_BUILDER_SANITATION="true";

             echo "Ahead-Of-Time compilation"
             $out/bin/native-image -H:+UnlockExperimentalVMOptions -H:-CheckToolchain -H:+ReportExceptionStackTraces HelloWorld
             ./helloworld | fgrep 'Hello World'

             ${# --static is only available in Linux
             lib.optionalString ((system == "x86_64-linux" || system == "aarch64-linux") && !useMusl) ''
               echo "Ahead-Of-Time compilation with -H:+StaticExecutableWithDynamicLibC"
               $out/bin/native-image -H:+UnlockExperimentalVMOptions -H:+StaticExecutableWithDynamicLibC HelloWorld
               ./helloworld | fgrep 'Hello World'

               echo "Ahead-Of-Time compilation with --static"
               $out/bin/native-image --static HelloWorld
               ./helloworld | fgrep 'Hello World'
             ''}

             ${# --static is only available in Linux
             lib.optionalString ((system == "x86_64-linux" || system == "aarch64-linux") && useMusl) ''
               echo "Ahead-Of-Time compilation with --static and --libc=musl"
               $out/bin/native-image --static HelloWorld --libc=musl
               ./helloworld | fgrep 'Hello World'
             ''}

             runHook postInstallCheck
           '';
         } // extraArgs);
       in
       graalvm-oracle-ee;
   in
   {
        packages."x86_64-linux" = {
            default = graalvm-oracle-ee { system = "x86_64-linux"; pkgs = nixpkgs; src = graalvmX8664Linux; };
        };
        packages."aarch64-linux" = {
            default = graalvm-oracle-ee { system = "aarch64-linux"; pkgs = nixpkgs; src = graalvmAarch64Linux; };
        };
        packages."x86_64-darwin" = {
            default = graalvm-oracle-ee { system = "x86_64-darwin"; pkgs = nixpkgs; src = graalvmX8664Darwin; };
        };
        packages."aarch64-darwin" = {
            default = graalvm-oracle-ee { system = "aarch64-darwin"; pkgs = nixpkgs; src = graalvmAarch64Darwin; };
        };
    };
 }