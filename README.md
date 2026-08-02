# Generación de escenarios de movilidad urbana para la toma de decisiones en localidades de Bogotá

Simulación microscópica de movilidad urbana para las localidades de Bogotá, desarrollada como proyecto de grado en Ingeniería de Sistemas de la Pontificia Universidad Javeriana.

El proyecto integra datos reales de movilidad (Encuesta de Movilidad de Bogotá 2023 y aforos vehiculares HMD) en un pipeline ETL que genera los archivos de entrada necesarios para ejecutar simulaciones en **SUMO (Simulation of Urban MObility)**, junto con un módulo web para visualizar resultados y parametrizar nuevas simulaciones.

## Equipo

| Integrante | 
|---|
| Samuel Esteban Campos |
| Erick Salazar Suárez |
| Santiago Chitiva Contreras | 
| Felipe Andrés Garrido Flores |

**Director:** Ing. Andrés Oswaldo Calderón Romero

## Estructura del repositorio

src/pipeline/ → Módulos del pipeline ETL (extracción, transformación, carga)
src/simulation/ → Scripts de configuración y ejecución de SUMO
tests/ → Pruebas unitarias (pytest)
data/raw/ → Datos originales (enlace a Drive, no versionados)
data/processed/ → Archivos SUMO generados (.net.xml, .od, .rou.xml, .vtype.xml)
docs/ → SPMP, SRS, SDD, Plan de Pruebas, Informe Final
notebooks/ → Exploración de datos (Jupyter)

## Instalación

```bash
git clone https://github.com/<usuario>/movilidad-sumo-usaquen.git
cd movilidad-sumo-usaquen
python3 -m venv venv
source venv/bin/activate       # En Windows: venv\Scripts\activate
pip install -r requirements.txt
```

Requiere además tener instalado **SUMO 1.19+** ([sumo.dlr.de](https://sumo.dlr.de/docs/Downloads.php)) con `netconvert` y `duarouter` disponibles en el PATH.

## Metodología

El proyecto sigue un modelo de ciclo de vida híbrido: **CRISP-DM** para las fases de datos (Fase 1-2) y **Scrum** para la construcción del escenario de simulación (Fase 3), 
documentado en el SPMP (`docs/spmp/`).

## Estándares

IEEE 1058-1998 (SPMP) · IEEE 830-1998 (SRS) · ISO/IEC 12207:2008 · PEP 8