/**
 * @creation date: 15/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Ventana con las otras pólizas (de cualquier aseguradora) donde ya existe un asegurado, vehículo o
 *               ubicación. La abren las pestañas Asegurados, Vehículos y Ubicaciones con abrir(registroId, contextoId).
 *               Usa OtrasPolizasController.buscar.
 */
import { LightningElement, api, track } from 'lwc';
import { fechaVisible } from 'c/lectorArchivos';
import buscar from '@salesforce/apex/OtrasPolizasController.buscar';

export default class OtrasPolizas extends LightningElement {
    abierto = false;
    cargando = false;
    error = '';
    titulo = '';
    @track resultado = null;

    /**
     * Abre la ventana y busca el registro en otras pólizas.
     * @param registroId participante, integrante del censo, inciso, bien de póliza o renglón de ubicaciones.
     * @param contextoId póliza u oportunidad que se está viendo.
     * @param titulo nombre del registro para el encabezado.
     */
    @api
    async abrir(registroId, contextoId, titulo) {
        this.abierto = true;
        this.cargando = true;
        this.error = '';
        this.resultado = null;
        this.titulo = titulo || '';
        try {
            this.resultado = await buscar({ registroId, contextoId });
        } catch (e) {
            this.error = (e && e.body && e.body.message) || (e && e.message) || 'No se pudo buscar en otras pólizas.';
        } finally {
            this.cargando = false;
        }
    }

    cerrar() { this.abierto = false; }
    handleTecla(e) { if (e.key === 'Escape') { this.cerrar(); } }

    get encabezado() { return this.titulo || (this.resultado && this.resultado.registro) || 'Otras pólizas'; }
    get filas() {
        return ((this.resultado && this.resultado.polizas) || []).map((p) => ({
            ...p,
            url: `/lightning/r/InsurancePolicy/${p.polizaId}/view`,
            vigenciaTxt: [fechaVisible(p.vigenciaInicio), fechaVisible(p.vigenciaFin)].filter((x) => x).join(' – ') || '—',
            aseguradoraTxt: p.aseguradora || 'Sin aseguradora',
            claseFila: p.otraAseguradora ? 'fila-otra' : '',
            registroTxt: p.vigente ? 'Vigente en esa póliza' : `Dado de baja${p.fechaBaja ? ' el ' + fechaVisible(p.fechaBaja) : ''}`,
            claseRegistro: 'estado ' + (p.vigente ? 'estado-vigente' : 'estado-baja')
        }));
    }
    get hayFilas() { return this.filas.length > 0; }
    get sinFilas() { return !this.cargando && !this.error && this.resultado && !this.hayFilas; }
    get otrasAseguradoras() { return this.filas.filter((p) => p.otraAseguradora).length; }
    get resumen() {
        const n = this.filas.length;
        if (!n) { return ''; }
        const otras = this.otrasAseguradoras;
        return `Existe en ${n} ${n === 1 ? 'póliza más' : 'pólizas más'}`
            + (otras ? `, ${otras} de otra aseguradora` : '')
            + (this.resultado.aseguradoraActual ? ` (esta póliza es de ${this.resultado.aseguradoraActual})` : '') + '.';
    }
    get criterio() { return this.resultado ? this.resultado.criterio : ''; }
}
