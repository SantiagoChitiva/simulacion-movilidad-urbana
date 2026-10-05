from pathlib import Path
from etl.sumo.simulation import SimulationConfig

def test_args_with_overrides():
    cfg = SimulationConfig(Path("x.sumocfg"), seed=7, begin=100, end=200)
    args = cfg.to_args()
    assert args[:2] == ["-c", "x.sumocfg"]
    assert args[args.index("--seed") + 1] == "7"
    assert args[args.index("--end") + 1] == "200"
