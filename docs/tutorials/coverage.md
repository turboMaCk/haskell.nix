# Coverage

haskell.nix can generate coverage information for your package or
project using Cabal's inbuilt hpc support.

## Prerequisites

To get a sensible coverage report, you need to enable coverage on each
of the components of your project:

```nix
pkgs.haskell-nix.project {
  src = pkgs.haskell-nix.haskellLib.cleanGit {
    name = "haskell-nix-project";
    src = ./.;
  };
  compiler-nix-name = "ghc884";

  modules = [{
    packages.$pkg.components.library.doCoverage = true;
    packages.$pkg.components.tests.a-test.doCoverage = true;
  }];
}
```

If you would like to make coverage optional, add an argument to your nix expression:

```nix
{ withCoverage ? false }:

pkgs.haskell-nix.project {
  src = pkgs.haskell-nix.haskellLib.cleanGit {
    name = "haskell-nix-project";
    src = ./.;
  };
  compiler-nix-name = "ghc884";

  modules = pkgs.lib.optional withCoverage [{
    packages.$pkg.components.library.doCoverage = true;
    packages.$pkg.components.tests.a-test.doCoverage = true;
  }];
}
```

## Per-package

```bash
nix-build default.nix -A "projectWithCoverage.$pkg.coverageReport"
```

This will generate a coverage report for the package you requested.
All tests that are enabled (configured with `doCheck == true`) are
included in the coverage report.

See the [developer coverage docs](../dev/coverage.md#package-reports) for more information.

## Project-wide

```bash
nix-build default.nix -A "projectWithCoverage.projectCoverageReport"
```

This will generate a coverage report for all the local packages in
your project.

See the [developer coverage docs](../dev/coverage.md#project-wide-reports) for more information.

## Custom

By default, `projectCoverageReport` generates a coverage report
including all the packages in your project, and `coverageReport`
generates a report for the library and all enabled tests in the
requested package. You can modify what is included in each report by
using the `coverageReport` and `projectCoverageReport` functions.
These are found in the haskell.nix library:

```nix
let
  inherit (pkgs.haskell-nix) haskellLib;

  project = haskellLib.project {
    src = pkgs.haskell-nix.haskellLib.cleanGit {
      name = "haskell-nix-project";
      src = ./.;
    };
    compiler-nix-name = "ghc884";

    modules = [{
      packages.$pkgA.components.library.doCoverage = true;
      packages.$pkgB.components.library.doCoverage = true;
    }];
  };

  # Choose the library and tests you want included in the coverage
  # report for a package.
  custom$pkgACoverageReport = haskellLib.coverageReport {
    name = "$pkgA-unit-tests-only"
    inherit (project.$pkgA.components) library;
    checks = [project.$pkgA.components.checks.unit-test];
  };

  custom$pkgBCoverageReport = haskellLib.coverageReport {
    name = "$pkgB-unit-tests-only"
    inherit (project.$pkgB.components) library;
    checks = [project.$pkgB.components.checks.unit-test];
  };

  # Override the coverage report for a package, and also choose which
  # packages you want included in the coverage report.
  allUnitTestsProjectReport = haskellLib.projectCoverageReport [custom$pkgACoverageReport custom$pkgBCoverageReport];
in {
  inherit project custom$pkgACoverageReport custom$pkgBCoverageReport allUnitTestsProjectCoverageReport;
}

```
