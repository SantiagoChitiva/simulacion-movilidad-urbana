import geopandas as gpd
import xml.etree.ElementTree as ET
from xml.dom import minidom

print("Cargando Zonas_ZAT.shp...")
gdf = gpd.read_file("Zonas_ZAT.shp")

# 1. Reproyectar a UTM 18N
print("Reproyectando ZATs a EPSG:32618 (UTM Zone 18N)...")
gdf = gdf.to_crs(epsg=32618)

# 2. Offset extraído de tu usaquen_major.net.xml
offset_x = -602189.69
offset_y = -515351.67

root = ET.Element("tazs")

col_zat = "ZAT" if "ZAT" in gdf.columns else ("objectid" if "objectid" in gdf.columns else gdf.columns[0])
print(f"Usando columna '{col_zat}' como identificador de ZAT.")

count = 0
for idx, row in gdf.iterrows():
    zat_id = str(row[col_zat])
    geom = row.geometry

    if geom is None:
        continue

    polygons = [geom] if geom.geom_type == "Polygon" else list(geom.geoms)

    for i, poly in enumerate(polygons):
        # Restar el offset para alinear con las coordenadas locales de SUMO (0,0)
        coords_str = " ".join([f"{(pt[0] + offset_x):.2f},{(pt[1] + offset_y):.2f}" for pt in poly.exterior.coords])

        taz_id_str = f"ZAT_{zat_id}" if len(polygons) == 1 else f"ZAT_{zat_id}_{i}"

        ET.SubElement(
            root,
            "taz",
            id=taz_id_str,
            shape=coords_str
        )
        count += 1

xml_bytes = ET.tostring(root, encoding="utf-8")
parsed = minidom.parseString(xml_bytes)
pretty_xml = parsed.toprettyxml(indent="  ")

with open("usaquen.taz.xml", "w", encoding="utf-8") as f:
    f.write(pretty_xml)

print(f"¡Éxito! Se generó 'usaquen.taz.xml' alineado con la red.")
