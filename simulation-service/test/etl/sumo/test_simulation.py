from pathlib import Path
from etl.sumo.simulation import SimulationConfig

def test_args_with_overrides():
    cfg = SimulationConfig(Path("x.sumocfg"), seed=7, begin=100, end=200)
    args = cfg.to_args()
    assert args[:2] == ["-c", "x.sumocfg"]
    assert args[args.index("--seed") + 1] == "7"
    assert args[args.index("--end") + 1] == "200"


def test_clasificar_eventos_separa_peatones_de_choques(tmp_path):
    from etl.sumo.simulation import clasificar_eventos

    log = tmp_path / "sumo.log"
    log.write_text(
        "Warning: Vehicle 'bus_T1_A.1.1' collision with person 'transporte_publico_5', lane='e_0', gap=-0.9, time=10.00, stage=move.\n"
        "Warning: Vehicle 'bus_T1_A.1.1' collision with person 'transporte_publico_5', lane='e_0', gap=-0.5, time=11.00, stage=move.\n"
        "Warning: Vehicle 'auto_3' collision with person 'peaton_2', lane='f_0', gap=-1.0, time=12.00, stage=move.\n"
        "Warning: Teleporting vehicle 'moto_1'; collision with vehicle 'bici_2', lane='g_1', gap=-4.2, time=13.00, stage=move.\n"
        "Warning: Teleporting vehicle 'tm_B46_X.1.2'; waited too long (jam), lane='h_0', time=14.00.\n"
        "Warning: Teleporting vehicle 'auto_9'; waited too long (yield), lane='h_0', time=15.00.\n",
        encoding="utf-8",
    )
    assert clasificar_eventos(log) == {
        "colisiones_con_peatones": 2,      # la pareja repetida cuenta una vez
        "colisiones_entre_vehiculos": 1,
        "teleports_buses": 1,
    }
    assert clasificar_eventos(tmp_path / "no_existe.log") == {}
