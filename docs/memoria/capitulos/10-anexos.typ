= Anexos

Los anexos están en el repositorio del proyecto, en la carpeta `docs/`, y se compilan a PDF con Typst.

#figure(
  table(
    columns: (10%, 1fr, 1fr),
    table.header([*Anexo*], [*Documento*], [*Ubicación*]),
    [A], [Plan de gestión del proyecto (SPMP), versión 2.2], [`docs/spmp/spmp.pdf`],
    [B], [Especificación de requerimientos (SRS), versión 2.2], [`docs/srs/srs.pdf`],
    [C], [Documento de diseño (SDD), versión 1.0], [`docs/sdd/sdd.pdf`],
    [D], [Propuesta del trabajo de grado (VFP)], [`docs/vfp/vfp.pdf`],
    [E], [Informe de brechas de las fuentes de datos (F1.4)], [`docs/f1/F1.4_informe_brechas.md`],
    [F], [Diseño del módulo de semaforización y del simulador 3D], [`docs/propuesta-semaforizacion-3d.md`],
    [G], [Código fuente, notebooks y guía de instalación], [Repositorio del proyecto (`README.md`, `simulation-service/`, `kepler/`, `notebooks/`)],
  ),
  caption: [Lista de anexos.],
)
