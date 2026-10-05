import pandas as pd
import xml.etree.ElementTree as ET
from xml.dom import minidom

# 1. Cargar viajes limpios
df = pd.read_csv("viajes_limpio.tsv", sep="\t")

# 2. Mapear modos
modo_map = {
    "AUTO": "passenger",
    "BICICLETA": "bicycle",
    "A PIE > 15 MIN": "pedestrian",
    "A PIE <15 MIN": "pedestrian"
}

df_vehicular = df[df["modo_principal_agrupado"].isin(["AUTO", "BICICLETA"])].copy()
df_vehicular = df_vehicular.sort_values(by="hora_ini_seg")

root = ET.Element("routes")

ET.SubElement(root, "vType", id="passenger", vClass="passenger")
ET.SubElement(root, "vType", id="bicycle", vClass="bicycle")

trip_id = 0
for _, row in df_vehicular.iterrows():
    zat_from = f"ZAT_{int(row['zat_ori'])}"
    zat_to = f"ZAT_{int(row['zat_des'])}"
    depart_time = float(row["hora_ini_seg"])
    modo = modo_map.get(row["modo_principal_agrupado"], "passenger")

    num_vehiculos = max(1, int(round(row["fexp_vj"])))

    for i in range(num_vehiculos):
        staggered_depart = round(depart_time + (i * 0.5), 1)

        ET.SubElement(
            root,
            "trip",
            id=f"trip_{trip_id}",
            type=modo,
            depart=str(staggered_depart),
            fromTaz=zat_from,
            toTaz=zat_to
        )
        trip_id += 1

xml_bytes = ET.tostring(root, encoding="utf-8")
pretty_xml = minidom.parseString(xml_bytes).toprettyxml(indent="  ")

with open("usaquen_od.trips.xml", "w", encoding="utf-8") as f:
    f.write(pretty_xml)

print(f"¡Éxito! Se generaron {trip_id} viajes en 'usaquen_od.trips.xml'.")
