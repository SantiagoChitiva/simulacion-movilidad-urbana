# ETL

Módulo encargado de transformar datos de movilidad y otras fuentes de información en los archivos de entrada requeridos por **SUMO (Simulation of Urban MObility)**.

Este módulo tiene como objetivo preparar datos reales de movilidad y datos geográficos, como los obtenidos de **OpenStreetMap (OSM)**.

---

## Objetivo

El ETL tiene como objetivo realizar el proceso de transformación de los datos de entrada en los diferentes archivos que requiere SUMO para construir y ejecutar una simulación.

De forma general, el flujo esperado es:

```text
Datos de entrada
      │
      ├── Encuestas de movilidad
      ├── Datos geográficos (OSM)
      └── Otros datos
      │
      ▼
     ETL
      │
      ├── Extracción
      ├── Transformación
      └── Generación
      │
      ▼
Archivos de entrada para SUMO
      │
      ├── .net.xml
      ├── .rou.xml
      ├── .add.xml
      └── .sumocfg
      │
      ▼
     SUMO
```

La idea es que los datos reales puedan ser procesados y posteriormente representados dentro de una simulación de movilidad.

---

## Estructura

Actualmente el módulo tiene la siguiente estructura:

```text
etl/
├── tests/
│
├── src/
│   └── etl/
│       ├── sumo/
│       │   ├── network.py
│       │   ├── configuration.py
│       │   └── __init__.py
│       │
│       ├── etl.py
│       └── __init__.py
│
├── pyproject.toml
└── README.md
```

### `src/etl/`

Contiene el código fuente del módulo ETL.

### `src/etl/etl.py`

Es el **punto de entrada y orquestador principal** del ETL.

Su responsabilidad es coordinar los diferentes procesos del módulo.

La lógica específica de cada proceso debe mantenerse en sus respectivos módulos para evitar concentrar toda la implementación en `etl.py`.

Por ejemplo:

```text
etl.py
   │
   ├── network.py
   │
   ├── configuration.py
   │
   ├── pedestrians.py
   │
   ├── vehicles.py
   │
   └── routes.py
```

### `src/etl/sumo/`

Contiene los módulos encargados de generar o preparar los diferentes insumos utilizados por SUMO.

Actualmente:

| Archivo            | Responsabilidad                                  |
| ------------------ | ------------------------------------------------ |
| `network.py`       | Generación/procesamiento de la red de simulación |
| `configuration.py` | Generación o gestión de la configuración de SUMO |

> [!TIP]
> Los módulos se organizan según el tipo de insumo que producen o gestionan para SUMO. Esto permite mantener cada proceso independiente y facilita la incorporación de nuevos tipos de datos.

### `tests/`

Contiene las pruebas automatizadas del módulo.

---

# `pyproject.toml`

`pyproject.toml` es el archivo estándar de configuración utilizado por los proyectos Python modernos.

En este proyecto contiene la configuración necesaria para que Python pueda identificar e instalar el módulo, incluyendo información como:

* Nombre del proyecto.
* Versión.
* Versión de Python requerida.
* Dependencias.
* Sistema de construcción del paquete.
* Configuración de herramientas de desarrollo.

Por ejemplo, el proyecto puede instalarse mediante:

```bash
pip install -e .
```

La opción `-e` significa **editable**.

Esto permite instalar el proyecto en el entorno virtual manteniendo el código fuente en su ubicación original. Por lo tanto, los cambios realizados en el código fuente se reflejan inmediatamente sin necesidad de reinstalar el proyecto después de cada modificación.

> [!NOTE]
> `pyproject.toml` describe y configura el proyecto Python. No debe utilizarse para almacenar contraseñas, tokens u otros secretos.

---

# Requisitos

Para ejecutar el ETL se requiere:

* Python 3.11 o superior.
* `pip`.
* SUMO y sus herramientas correspondientes cuando sean necesarias para generar los archivos de simulación.

La versión exacta de Python soportada por el proyecto se encuentra definida en `pyproject.toml`.

> [!IMPORTANT]
> Se recomienda utilizar un entorno virtual de Python para evitar conflictos entre las dependencias del ETL y las dependencias instaladas globalmente en el sistema.

---

# Configuración del entorno

Se recomienda crear un entorno virtual específico para el módulo ETL.

Desde la raíz del repositorio:

```bash
cd etl
```

Crear el entorno virtual:

```bash
python3 -m venv .venv
```

Activarlo:

### Linux / macOS

```bash
source .venv/bin/activate
```

### Windows

```powershell
.venv\Scripts\activate
```

Una vez activado, el terminal debería mostrar algo similar a:

```text
(.venv) usuario@maquina:~/proyecto/etl$
```

> [!WARNING]
> No es necesario subir `.venv/` al repositorio. El entorno virtual contiene dependencias específicas de la máquina y debe estar incluido en `.gitignore`.

---

# Instalación

Con el entorno virtual activo, instalar el proyecto en modo editable:

```bash
pip install -e .
```

Esto instalará el proyecto definido en `pyproject.toml` dentro del entorno virtual.

Si posteriormente se agregan o modifican dependencias en `pyproject.toml`, ejecutar nuevamente:

```bash
pip install -e .
```

---

# Ejecución

El ETL se ejecuta como un módulo Python.

Desde el directorio `etl/` y con el entorno virtual activo:

```bash
python -m etl.etl
```

La estructura del comando es:

```text
python -m etl.etl
          │  │
          │  └── archivo etl.py
          └───── paquete etl
```

Esto permite ejecutar `etl.py` como parte del paquete Python `etl`.

El archivo `etl.py` funciona como el **orquestador principal** del proceso.

---

# Flujo de instalación y ejecución

Para una instalación inicial:

```bash
cd etl

python3 -m venv .venv

source .venv/bin/activate

pip install -e .

python -m etl.etl
```

> [!TIP]
> En sesiones posteriores no es necesario crear nuevamente el entorno virtual. Basta con activarlo y ejecutar el ETL:

```bash
cd etl

source .venv/bin/activate

python -m etl.etl
```

---

# Desarrollo

Durante el desarrollo, cada componente debe mantener una responsabilidad específica.

Por ejemplo:

```text
                 etl.py
                   │
          ┌────────┼────────┐
          │        │        │
          ▼        ▼        ▼
      network  pedestrians vehicles
          │        │        │
          ▼        ▼        ▼
       .net.xml  .rou.xml  .rou.xml
```

El archivo `etl.py` coordina estos componentes, mientras que los módulos especializados contienen la lógica necesaria para generar cada tipo de insumo.

Esto permite que el ETL pueda crecer progresivamente sin convertir el archivo principal en un único archivo con toda la lógica del sistema.

> [!NOTE]
> La estructura actual es intencionalmente sencilla. Se evitará agregar abstracciones o componentes que no sean necesarios hasta que los requerimientos del ETL los justifiquen.

---

# Estado actual

El módulo se encuentra en una etapa inicial de desarrollo.

Actualmente se está estableciendo la estructura base para la generación de los archivos requeridos por SUMO.

Los siguientes componentes se incorporarán progresivamente:

* Generación de la red vial a partir de datos de OSM.
* Procesamiento de encuestas de movilidad.
* Generación de peatones.
* Generación de vehículos.
* Generación de rutas.
* Generación de archivos adicionales de SUMO.
* Generación de diferentes configuraciones de simulación.

El objetivo final es que el ETL permita transformar los datos reales de movilidad en diferentes configuraciones reproducibles de simulación para SUMO.
