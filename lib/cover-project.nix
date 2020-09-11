# A project coverage report is a composition of package coverage
# reports
{ pkgs, lib, haskellLib }:

# List of coverage reports to accumulate
coverageReports:

let
  # Create table rows for a project coverage index page that look something like:
  #
  # | Package          |
  # |------------------|
  # | cardano-shell    |
  # | cardano-launcher |
  coverageTableRows = coverageReport:
      ''
      <tr>
        <td>
          <a href="${coverageReport.passthru.name}/hpc_index.html">${coverageReport.passthru.name}</href>
        </td>
      </tr>
      '';

  projectIndexHtml = pkgs.writeText "index.html" ''
  <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    </head>
    <body>
      <table border="1" width="100%">
        <tbody>
          <tr>
            <th>Report</th>
          </tr>

          ${with lib; concatStringsSep "\n" (map coverageTableRows coverageReports)}

        </tbody>
      </table>
    </body>
  </html>
  '';

  ghc =
    if (builtins.length coverageReports) > 0
    then (builtins.head coverageReports).library.project.pkg-set.config.ghc.package or pkgs.ghc
    else pkgs.ghc;

in pkgs.runCommand "project-coverage-report"
  { buildInputs = [ghc]; }
  ''
    mkdir -p $out/share/hpc/vanilla/tix/all
    mkdir -p $out/share/hpc/vanilla/mix/
    mkdir -p $out/share/hpc/vanilla/html/

    # Find all tix files in each package
    tixFiles=()
    ${with lib; concatStringsSep "\n" (map (coverageReport: ''
      identifier="${coverageReport.name}"
      report=${coverageReport}
      tix="$report/share/hpc/vanilla/tix/$identifier/$identifier.tix"
      if test -f "$tix"; then
        tixFiles+=("$tix")
      fi

      # Copy mix and tix information over from each report
      cp -R $report/share/hpc/vanilla/mix/* $out/share/hpc/vanilla/mix
      cp -R $report/share/hpc/vanilla/tix/* $out/share/hpc/vanilla/tix
      cp -R $report/share/hpc/vanilla/html/* $out/share/hpc/vanilla/html
    '') coverageReports)}

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
