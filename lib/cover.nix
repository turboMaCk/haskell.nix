{ stdenv, lib, haskellLib, pkgs }:

# Name of the coverage report, which should be unique
{ name
# Library to check coverage of
, library
# List of check derivations that generate coverage
, checks
# Should the tests of one local package generate coverage for another
# local package?
, crossPollinate ? true
}:

let
  toBashArray = arr: "(" + (lib.concatStringsSep " " arr) + ")";

  # Exclude test modules from tix file. Getting coverage information
  # for the test modules doesn't make sense as we're interested in how
  # much the tests covered the library, not how much the tests covered
  # themselves.
  #
  # The Main module is hard-coded here because the Main module is not
  # listed in "$test.config.modules" (the plan.nix) but must be
  # excluded. Note that the name of the Main module file does not
  # matter. So a line in your cabal file such as: "main-is: Spec.hs"
  # still generates a "Main.mix" file with the contents: Mix
  # "Spec.hs". Hence we can hardcode the name "Main" here.
  testModules = lib.foldl' (acc: test: acc ++ test.config.modules) ["Main"] checks;

  # Libraries in the project
  projectLibs = map (pkg: pkg.components.library) (lib.attrValues (haskellLib.selectProjectPackages library.project.hsPkgs));

  # Mix information HPC will need
  mixDirs =
    map
      (l: "${l}/share/hpc/vanilla/mix/${l.identifier.name}-${l.identifier.version}")
      (if crossPollinate then projectLibs else [library]);

  # Src information HPC will need
  srcDirs = map (l: l.src.outPath) (if crossPollinate then projectLibs else [library]);

  ghc = library.project.pkg-set.config.ghc.package;

in pkgs.runCommand (name + "-coverage-report")
  ({ buildInputs = [ ghc ];
    passthru = {
      inherit name library checks;
    };
    # HPC will fail if the Haskell file contains non-ASCII characters,
    # unless our locale is set correctly. This has been fixed, but we
    # don't know what version of HPC we will be using, hence we should
    # always use the workaround.
    # https://gitlab.haskell.org/ghc/ghc/-/issues/17073
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  } // lib.optionalAttrs (stdenv.buildPlatform.libc == "glibc") {
    LOCALE_ARCHIVE = "${pkgs.buildPackages.glibcLocales}/lib/locale/locale-archive";
  })
  ''
    function markup() {
      local -n srcDs=$1
      local -n mixDs=$2
      local -n includedModules=$3
      local destDir=$4
      local tixFile=$5

      local hpcMarkupCmd=("hpc" "markup" "--destdir=$destDir")
      for srcDir in "''${srcDs[@]}"; do
        hpcMarkupCmd+=("--srcdir=$srcDir")
      done

      for mixDir in "''${mixDs[@]}"; do
        hpcMarkupCmd+=("--hpcdir=$mixDir")
      done

      for module in "''${includedModules[@]}"; do
        hpcMarkupCmd+=("--include=$module")
      done

      hpcMarkupCmd+=("$tixFile")

      echo "''${hpcMarkupCmd[@]}"
      eval "''${hpcMarkupCmd[@]}"
    }

    function sumTix() {
      local -n includedModules=$1
      local -n tixFs=$2
      local outFile="$3"

      local hpcSumCmd=("hpc" "sum" "--union" "--output=$outFile")

      for module in "''${includedModules[@]}"; do
        hpcSumCmd+=("--include=$module")
      done

      for tixFile in "''${tixFs[@]}"; do
        hpcSumCmd+=("$tixFile")
      done

      echo "''${hpcSumCmd[@]}"
      eval "''${hpcSumCmd[@]}"
    }

    function discoverPackageModules() {
      pushd $out/share/hpc/vanilla/mix/${name}
      mapfile -d $'\0' $1 < <(find ./ -type f \
        -wholename "*.mix" -not -name "Paths*" \
        -exec basename {} \; \
        | sed "s/\.mix$//" \
        | tr "\n" "\0")
      popd
    }


    local mixDirs=${toBashArray mixDirs}

    mkdir -p $out/share/hpc/vanilla/mix/${name}
    mkdir -p $out/share/hpc/vanilla/tix/${name}
    mkdir -p $out/share/hpc/vanilla/html/${name}

    # Copy over mix files verbatim
    for dir in "''${mixDirs[@]}"; do
      if [ -d "$dir" ]; then
        cp -R "$dir"/* $out/share/hpc/vanilla/mix/${name}
      fi
    done

    local srcDirs=${toBashArray srcDirs}
    local pkgModules=()
    discoverPackageModules pkgModules
    echo "Included modules: ''${pkgModules[@]}"

    # Copy over tix files verbatim
    local tixFiles=()
    ${lib.concatStringsSep "\n" (builtins.map (check: ''
      if [ -d "${check}/share/hpc/vanilla/tix" ]; then
        pushd ${check}/share/hpc/vanilla/tix

        tixFile="$(find . -iwholename "*.tix" -type f -print -quit)"
        local newTixFile=$out/share/hpc/vanilla/tix/${name}/"$tixFile"

        mkdir -p "$(dirname $newTixFile)"
        cp "$tixFile" "$newTixFile"

        tixFiles+=("$newTixFile")

        markup srcDirs mixDirs pkgModules "$out/share/hpc/vanilla/html/${name}/${check.exeName}/" "$newTixFile"

        popd
      fi
    '') checks)
    }

    # Sum tix files to create a tix file with all relevant tix
    # information and markup a HTML report from this info.
    if (( "''${#tixFiles[@]}" > 0 )); then
      local testModules=${toBashArray testModules}
      local sumTixFile="$out/share/hpc/vanilla/tix/${name}/${name}.tix"
      local markupOutDir="$out/share/hpc/vanilla/html/${name}"

      # Turn found mix files into corresponding Haskell modules and
      # load into array

      sumTix pkgModules tixFiles "$sumTixFile"

      markup srcDirs mixDirs pkgModules "$markupOutDir" "$sumTixFile"
    fi
  ''
