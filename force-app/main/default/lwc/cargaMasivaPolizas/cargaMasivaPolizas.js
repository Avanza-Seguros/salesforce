/**
 * @creation date: 16/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Carga masiva de pólizas desde PDFs de carátula. Cada PDF se procesa con el mismo flujo que la carga
 * manual de Crear Póliza (c-policy-creator, sin oportunidad): se lee el texto, la IA extrae los datos y se crea la
 * póliza o, si ya existe con el mismo número y vigencia, se complementa. Se procesan varios a la vez, se puede
 * pausar y los PDFs ya procesados se recuerdan en este navegador para retomar la carga.
 */
import { LightningElement } from 'lwc';

const LLAVE_HECHOS = 'cargaMasivaPolizas.procesados';
// Tiempo máximo por PDF antes de darlo por fallido.
const TIEMPO_MAXIMO_MS = 6 * 60 * 1000;

export default class CargaMasivaPolizas extends LightningElement {
    archivos = [];
    resultados = [];
    simultaneos = 3;
    saltarProcesados = true;
    procesando = false;
    pausado = false;
    // Un c-policy-creator por proceso en curso; se vuelve a crear (llave nueva) para cada PDF.
    ranuras = [];
    _cola = [];
    _secuencia = 0;
    _hechos = {};

    connectedCallback() {
        try {
            this._hechos = JSON.parse(window.localStorage.getItem(LLAVE_HECHOS) || '{}') || {};
        } catch (e) {
            this._hechos = {};
        }
    }

    get totalArchivos() { return this.archivos.length; }
    get yaProcesados() { return this.archivos.filter((f) => this._hechos[f.name]).length; }
    get hayArchivos() { return this.archivos.length > 0; }
    get hayResultados() { return this.resultados.length > 0; }
    get sinIniciar() { return !this.hayArchivos || this.procesando; }
    get noProcesando() { return !this.procesando; }
    get textoPausa() { return this.pausado ? 'Continuar' : 'Pausar'; }
    get pendientes() { return this._cola.length + this.ranuras.length; }
    get cuenta() {
        const c = { creada: 0, actualizada: 0, error: 0, saltada: 0 };
        this.resultados.forEach((r) => { c[r.estado] = (c[r.estado] || 0) + 1; });
        return c;
    }
    get avance() {
        const total = this.resultados.length + this.pendientes;
        return total ? Math.round((this.resultados.length * 100) / total) : 0;
    }
    get estiloAvance() { return `width:${this.avance}%`; }
    get resultadosVista() {
        return this.resultados.slice().reverse().slice(0, 300).map((r) => ({
            ...r,
            url: r.policyId ? `/lightning/r/InsurancePolicy/${r.policyId}/view` : null,
            clase: `chip chip--${r.estado}`,
            textoMensajes: (r.mensajes || []).join(' · ')
        }));
    }

    handleArchivos(event) {
        this.archivos = Array.from(event.target.files || []).filter((f) => /\.pdf$/i.test(f.name));
    }

    handleSimultaneos(event) {
        const n = parseInt(event.target.value, 10);
        this.simultaneos = Math.min(5, Math.max(1, Number.isNaN(n) ? 1 : n));
    }

    handleSaltar(event) {
        this.saltarProcesados = event.target.checked;
    }

    handleIniciar() {
        if (!this.hayArchivos || this.procesando) { return; }
        this.resultados = [];
        this._cola = [];
        this.archivos.forEach((f) => {
            if (this.saltarProcesados && this._hechos[f.name]) {
                this.resultados.push(this.fila(f, { estado: 'saltada', mensajes: ['Ya se había procesado en este navegador.'] }));
            } else {
                this._cola.push(f);
            }
        });
        this.resultados = [...this.resultados];
        this.procesando = true;
        this.pausado = false;
        this.llenarRanuras();
    }

    handlePausa() {
        this.pausado = !this.pausado;
        if (!this.pausado) { this.llenarRanuras(); }
    }

    // Arranca procesos hasta completar los simultáneos permitidos.
    llenarRanuras() {
        while (!this.pausado && this._cola.length && this.ranuras.length < this.simultaneos) {
            const archivo = this._cola.shift();
            this._secuencia += 1;
            const ranura = { key: `r${this._secuencia}`, archivo };
            this.ranuras = [...this.ranuras, ranura];
            this.procesar(ranura);
        }
        if (!this._cola.length && !this.ranuras.length) {
            this.procesando = false;
        }
    }

    async procesar(ranura) {
        let resultado;
        try {
            const creador = await this.creadorDe(ranura.key);
            const limite = new Promise((resolve) => {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => resolve({ estado: 'error', mensajes: ['Tiempo agotado procesando el PDF.'] }), TIEMPO_MAXIMO_MS);
            });
            resultado = creador
                ? await Promise.race([creador.procesarPdf(ranura.archivo), limite])
                : { estado: 'error', mensajes: ['No se pudo iniciar el creador de pólizas.'] };
        } catch (e) {
            resultado = { estado: 'error', mensajes: [(e && e.body && e.body.message) || (e && e.message) || 'Error inesperado.'] };
        }
        this.resultados = [...this.resultados, this.fila(ranura.archivo, resultado)];
        if (resultado.estado === 'creada' || resultado.estado === 'actualizada') {
            this._hechos[ranura.archivo.name] = resultado.policyId || true;
            try { window.localStorage.setItem(LLAVE_HECHOS, JSON.stringify(this._hechos)); } catch (e) { /* sin almacenamiento */ }
        }
        this.ranuras = this.ranuras.filter((r) => r.key !== ranura.key);
        this.llenarRanuras();
    }

    // Espera a que se pinte el c-policy-creator de la ranura.
    async creadorDe(key) {
        for (let i = 0; i < 50; i++) {
            const el = this.template.querySelector(`c-policy-creator[data-key="${key}"]`);
            if (el) { return el; }
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((r) => { setTimeout(r, 100); });
        }
        return null;
    }

    // Archivo descargado de PRD: "<PolizaPRD>__<ContentDocumentId>.pdf".
    fila(archivo, r) {
        const base = archivo.name.replace(/\.pdf$/i, '');
        const partes = base.split('__');
        return {
            key: `${archivo.name}-${this.resultados.length}-${Date.now()}`,
            archivo: archivo.name,
            polizaOrigen: partes.length > 1 ? partes[0] : '',
            numero: r.numero || '',
            estado: r.estado,
            policyId: r.policyId || null,
            mensajes: r.mensajes || []
        };
    }

    handleOlvidar() {
        this._hechos = {};
        try { window.localStorage.removeItem(LLAVE_HECHOS); } catch (e) { /* sin almacenamiento */ }
        this.archivos = [...this.archivos];
    }

    handleDescargar() {
        const esc = (v) => `"${String(v == null ? '' : v).replace(/"/g, '""')}"`;
        const filas = [['Archivo', 'Poliza origen', 'Numero leido', 'Estado', 'InsurancePolicy Id', 'Mensajes']]
            .concat(this.resultados.map((r) => [r.archivo, r.polizaOrigen, r.numero, r.estado, r.policyId, (r.mensajes || []).join(' | ')]));
        const csv = '﻿' + filas.map((f) => f.map(esc).join(',')).join('\r\n');
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = 'carga_masiva_polizas.csv';
        a.click();
    }
}
