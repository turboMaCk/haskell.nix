{ pkgs, lib, haskellLib }:

# List of project packages to generate a coverage report for
{ packages
, coverageReportOverrides ? {}
}:

let
  getPackageCoverageReport = packageName: (coverageReportOverrides."${packageName}" or packages."${packageName}".coverageReport);

  # Create table rows for an project coverage index page that look something like:
  #
  # | Package          |
  # |------------------|
  # | cardano-shell    |
  # | cardano-launcher |
  packageTableRows = package: with lib;
    let
      testsOnly = filterAttrs (n: d: isDerivation d) package.components.tests;
      testNames = mapAttrsToList (testName: _: testName) testsOnly;
    in
      concatStringsSep "\n" (map (testName:
      ''
      <tr>
        <td>
          <a href="${package.identifier.name}-${package.identifier.version}/hpc_index.html">${package.identifier.name}</href>
        </td>
      </tr>
      '') testNames);

  projectIndexHtml = pkgs.writeText "index.html" ''
  <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    </head>
    <body>
      <table border="1" width="100%">
        <tbody>
          <tr>
            <th>Package</th>
          </tr>

          ${with lib; concatStringsSep "\n" (mapAttrsToList (_ : packageTableRows) packages)}

        </tbody>
      </table>
    </body>
  </html>
  '';

  ghc = let
    packageList = lib.attrValues packages;
  in
    if (builtins.length packageList) > 0
    then (builtins.head packageList).project.pkg-set.config.ghc.package
    else pkgs.ghc;

in pkgs.runCommand "project-coverage-report"
  { buildInputs = [ghc]; }
  ''
    mkdir -p $out/share/hpc/vanilla/tix/all
    mkdir -p $out/share/hpc/vanilla/mix/
    mkdir -p $out/share/hpc/vanilla/html/

    # Find all tix files in each package
    tixFiles=()
    ${with lib; concatStringsSep "\n" (mapAttrsToList (n: package: ''
      identifier="${package.identifier.name}-${package.identifier.version}"
      report=${getPackageCoverageReport n}
      tix="$report/share/hpc/vanilla/tix/$identifier/$identifier.tix"
      if test -f "$tix"; then
        tixFiles+=("$tix")
      fi

      # Copy mix and tix information over from each report
      cp -R $report/share/hpc/vanilla/mix/* $out/share/hpc/vanilla/mix
      cp -R $report/share/hpc/vanilla/tix/* $out/share/hpc/vanilla/tix
      cp -R $report/share/hpc/vanilla/html/* $out/share/hpc/vanilla/html
    '') packages)}

    if [ ''${#tixFiles[@]} -ne 0 ]; then
      # Create tix file with test run information for all packages
      tixFile="$out/share/hpc/vanilla/tix/all/all.tix"
      hpcSumCmd=("hpc" "sum" "--union" "--output=$tixFile")
      hpcSumCmd+=("''${tixFiles[@]}")
      echo "''${hpcSumCmd[@]}"
      eval "''${hpcSumCmd[@]}"

      # Markup a HTML coverage report for the entire project
      cp ${projectIndexHtml} $out/share/hpc/vanilla/html/index.html
    fi
  ''
