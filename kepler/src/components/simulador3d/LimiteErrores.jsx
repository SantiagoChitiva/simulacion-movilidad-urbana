import React from 'react';

/**
 * Si algo del simulador 3D falla al dibujarse, muestra el error en vez de desmontar
 * toda la aplicación (y cerrar la comparación en el servidor).
 */
export default class LimiteErrores extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('Simulador 3D:', error, info?.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="sim3d">
        <div className="sim3d-cortina">
          <p className="pd-error">El simulador 3D tuvo un error: {String(this.state.error.message ?? this.state.error)}</p>
          <button type="button" onClick={this.props.onCerrar}>Cerrar</button>
        </div>
      </div>
    );
  }
}
