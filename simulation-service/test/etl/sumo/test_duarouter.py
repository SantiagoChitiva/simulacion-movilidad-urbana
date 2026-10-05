from pathlib import Path
from etl.sumo.duarouter import DuarouterConfig

def test_args_include_flags():
    cfg = DuarouterConfig(Path("a.net.xml"), Path("t.xml"), Path("z.xml"), Path("o.xml"))
    args = cfg.to_args()
    assert "--ignore-errors" in args and "--repair" in args
    assert args[args.index("--routing-threads") + 1] == "4"
