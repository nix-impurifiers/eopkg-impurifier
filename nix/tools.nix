# SPDX-License-Identifier: MIT
{ pkgs }:
let
  python = pkgs.python312;
  py = python.pkgs;
  iksemel = py.buildPythonPackage {
    pname = "iksemel";
    version = "1.6.2";
    pyproject = true;
    src = pkgs.fetchurl {
      url = "https://github.com/Zaryob/iksemel/archive/5abdbce9721230553ae036abbcee9a938fd9e711.tar.gz";
      hash = "sha256-6+Q0ZCPxeK+8RmB5eQ/YT7Zgd0zxb38Me1P/lfkjVzo=";
    };
    build-system = [ py.setuptools ];
    env.NIX_CFLAGS_COMPILE = "-DHAVE_UNISTD_H=1";
    pythonImportsCheck = [ "iksemel" ];
  };
  lzmaMt = py.buildPythonPackage {
    pname = "lzma-mt";
    version = "0.2.1";
    pyproject = true;
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/70/3d/4cc608df2047ca66a79dbdccbd167134a09d4764299fe3d54f9156a8f892/lzma_mt-0.2.1.tar.gz";
      hash = "sha256-fWcGr9IGBwHqB/PGNYDVioZ0QFU46AiVjsVDRsbrCQk=";
    };
    build-system = [
      py.setuptools
      py.wheel
      py.cython
      py.setuptools-scm
    ];
    buildInputs = [ pkgs.xz ];
    env.SETUPTOOLS_SCM_PRETEND_VERSION = "0.2.1";
    pythonImportsCheck = [ "lzma_mt" ];
  };
  package = py.buildPythonPackage {
    pname = "eopkg";
    version = "5.0.0";
    pyproject = true;
    src = pkgs.fetchurl {
      url = "https://github.com/getsolus/package-management/archive/0b6692102a57d6b092a68c16e35f2d4f094cfd91.tar.gz";
      hash = "sha256-8U74zSwydovPMfKSSii1tQZVs1uZDIvpWJKCxNpj6IQ=";
    };
    build-system = [
      py.setuptools
      iksemel
      lzmaMt
      py.python-magic
      py.ordered-set
      py.requests
      py.rich
    ];
    dependencies = [
      iksemel
      lzmaMt
      py.ordered-set
      py.python-magic
      py.requests
      py.rich
      py.xattr
      py.jeepney
    ];
    nativeBuildInputs = [ pkgs.gettext ];
    pythonImportsCheck = [
      "pisi.package"
      "pisi.api"
    ];
  };
in
{
  inherit package;
  python = python.withPackages (_: [ package ]);
}
