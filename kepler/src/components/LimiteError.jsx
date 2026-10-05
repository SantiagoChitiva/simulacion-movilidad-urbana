import React from 'react';

/**
 * Si kepler falla al dibujar (p. ej. un tooltip que apunta a datos ya reemplazados),
 * muestra un aviso con un botón para reintentar en vez de dejar la página en blanco.
 */
export default class LimiteError extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error) {
    console.error('El mapa falló al dibujarse:', error);
  }

  reintentar = () => {
    this.props.onReintentar?.();
    this.setState({ error: null });
  };

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="limite-error" role="alert">
        <p>El mapa tuvo un problema al dibujarse.</p>
        <p className="pd-nota">{String(this.state.error?.message ?? this.state.error)}</p>
        <button type="button" onClick={this.reintentar}>
          Volver a dibujar el mapa
        </button>
      </div>
    );
  }
}
