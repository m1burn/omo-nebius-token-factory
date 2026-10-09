"""analyzers package: the analyzer set. Registry order = report row order."""

from analyzers.cs import CsAnalyzer
from analyzers.deadcode import DeadcodeAnalyzer
from analyzers.docker import DockerAnalyzer
from analyzers.dup import DupAnalyzer
from analyzers.jsts import JstsAnalyzer
from analyzers.md import MdAnalyzer
from analyzers.ps1 import Ps1Analyzer
from analyzers.py import PyAnalyzer
from analyzers.secrets import SecretsAnalyzer
from analyzers.sh import ShAnalyzer
from analyzers.tf import TfAnalyzer
from analyzers.yaml import YamlAnalyzer

ANALYZERS = (
    Ps1Analyzer(),
    ShAnalyzer(),
    PyAnalyzer(),
    JstsAnalyzer(),
    DockerAnalyzer(),
    TfAnalyzer(),
    YamlAnalyzer(),
    MdAnalyzer(),
    CsAnalyzer(),
    SecretsAnalyzer(),
    DupAnalyzer(),
    DeadcodeAnalyzer(),
)
