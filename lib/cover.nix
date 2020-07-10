{ lib, haskellLib, pkgs }:

{ name
, version
, library
, tests
}:

let
  identifier = name + "-" + version;
  toBashArray = arr: "(" + (lib.concatStringsSep " " arr) + ")";

  testsAsList = lib.attrValues tests;
  checks      = builtins.map (d: haskellLib.check d) testsAsList;

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
  testModules = lib.foldl' (acc: test: acc ++ test.config.modules) ["Main"] testsAsList;

  # Mix information HPC will need.
  # For libraries, where we copy the mix information from differs from
  # where HPC should look for the mix files. For tests, they are the
  # same location.
  mixInfo = [ { rootDir = "${library}/share/hpc/vanilla/mix";
                searchSubDir = "${identifier}";
              }
            ] ++ map (drv: { rootDir = "${drv}/share/hpc/vanilla/mix"; searchSubDir = null; }) testsAsList;

  mixDirs = map (info: info.rootDir) mixInfo;
  mixSearchDirs = map (info: if info.searchSubDir == null then info.rootDir else info.rootDir + "/" + info.searchSubDir) mixInfo;

  ghc = library.project.pkg-set.config.ghc.package;

in pkgs.runCommand (identifier + "-coverage-report")
  { buildInputs = [ ghc ]; }
  ''
    function markup() {
      local srcDir=$1
      local -n mixDs=$2
      local -n excludedModules=$3
      local destDir=$4
      local tixFile=$5

      local hpcMarkupCmd=("hpc" "markup" "--srcdir=$srcDir" "--destdir=$destDir")
      for mixDir in "''${mixDs[@]}"; do
        hpcMarkupCmd+=("--hpcdir=$mixDir")
      done

      for module in "''${excludedModules[@]}"; do
        hpcMarkupCmd+=("--exclude=$module")
      done

      hpcMarkupCmd+=("$tixFile")

      echo "''${hpcMarkupCmd[@]}"
      eval "''${hpcMarkupCmd[@]}"
    }

    function sumTix() {
      local -n excludedModules=$1
      local -n tixFs=$2
      local outFile="$3"

      local hpcSumCmd=("hpc" "sum" "--union" "--output=$outFile")

      for module in "''${excludedModules[@]}"; do
        hpcSumCmd+=("--exclude=$module")
      done

      for tixFile in "''${tixFs[@]}"; do
        hpcSumCmd+=("$tixFile")
      done

      echo "''${hpcSumCmd[@]}"
      eval "''${hpcSumCmd[@]}"
    }

    local mixDirs=${toBashArray mixDirs}

    mkdir -p $out/share/hpc/vanilla/mix/${identifier}
    mkdir -p $out/share/hpc/vanilla/tix/${identifier}
    mkdir -p $out/share/hpc/vanilla/html/${identifier}

    # Copy over mix files verbatim
    for dir in "''${mixDirs[@]}"; do
      if [ -d "$dir" ]; then
        cp -R "$dir"/* $out/share/hpc/vanilla/mix/
      fi
    done

    # Copy over tix files verbatim
    ${lib.optionalString ((builtins.length testsAsList) > 0) ''
      local tixFiles=()
      ${lib.concatStringsSep "\n" (builtins.map (check: ''
        if [ -d "${check}/share/hpc/vanilla/tix" ]; then
          pushd ${check}/share/hpc/vanilla/tix

          tixFile="$(find . -iwholename "*.tix" -type f -print -quit)"
          local newTixFile=$out/share/hpc/vanilla/tix/"$tixFile"

          mkdir -p "$(dirname $newTixFile)"
          cp "$tixFile" "$newTixFile"

          tixFiles+=("${check}/share/hpc/vanilla/tix/$tixFile")

          popd
        fi
      '') checks)
      }

      # Sum tix files to create a tix file with all relevant tix
      # information and markup a HTML report from this info.
      if (( "''${#tixFiles[@]}" > 0 )); then
        local src=${library.src.outPath}
        local mixSearchDirs=${toBashArray mixSearchDirs}
        local testModules=${toBashArray testModules}
        local sumTixFile="$out/share/hpc/vanilla/tix/${identifier}/${identifier}.tix"
        local markupOutDir="$out/share/hpc/vanilla/html/${identifier}"

        sumTix testModules tixFiles "$sumTixFile"

        markup "$src" mixSearchDirs testModules "$markupOutDir" "$sumTixFile"
      fi
    ''}
  ''
