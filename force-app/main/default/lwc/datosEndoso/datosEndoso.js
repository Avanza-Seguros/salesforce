/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Datos del endoso de la aseguradora para los movimientos de una póliza (asegurados, vehículos y
 *               ubicaciones): prima neta, derechos, IVA y prima total como vienen en el documento (no se calculan) y
 *               el documento del endoso, que se adjunta a la transacción del endoso (InsurancePolicyTransaction).
 */
import { LightningElement, api, track } from 'lwc';
import subirArchivo from '@salesforce/apex/MovimientosColectivoController.subirArchivo';
import { llamar } from 'c/portalContexto';

// Límite del archivo: se manda en base64 a Apex.
const MAX_BYTES = 3.5 * 1024 * 1024;

export default class DatosEndoso extends LightningElement {
    @track valores = {};
    archivo = null;
    archivoNombre = '';
    errorArchivo = '';

    get primaNeta() { return this.valores.primaNeta; }
    get derechos() { return this.valores.derechos; }
    get iva() { return this.valores.iva; }
    get total() { return this.valores.total; }

    // Prima leída del documento del endoso (se puede corregir).
    @api
    get valoresIniciales() { return this._valoresIniciales; }
    set valoresIniciales(v) {
        this._valoresIniciales = v;
        if (v) { this.valores = { ...v }; }
    }
    // Documento del endoso que ya se subió para leerlo: se adjunta sin volver a elegirlo.
    @api
    get archivoInicial() { return this._archivoInicial; }
    set archivoInicial(f) {
        this._archivoInicial = f;
        if (!f) { return; }
        if (f.size > MAX_BYTES) {
            this.errorArchivo = 'El archivo pesa más de 3.5 MB: adjúntalo después en la transacción del endoso.';
            return;
        }
        this.archivo = f;
        this.archivoNombre = f.name;
    }

    handleCampo(e) {
        const v = e.target.value;
        this.valores = { ...this.valores, [e.target.dataset.campo]: v === '' || v === null || v === undefined ? null : Number(v) };
    }

    handleArchivo(e) {
        const f = e.target.files && e.target.files[0];
        this.errorArchivo = '';
        if (f && f.size > MAX_BYTES) {
            this.archivo = null;
            this.archivoNombre = '';
            this.errorArchivo = 'El archivo pesa más de 3.5 MB: adjúntalo después en la transacción del endoso.';
            e.target.value = null;
            return;
        }
        this.archivo = f || null;
        this.archivoNombre = f ? f.name : '';
    }

    /** Prima del endoso capturada, o null si no se capturó nada. */
    @api
    get prima() {
        const v = this.valores;
        const hay = ['primaNeta', 'derechos', 'iva', 'total'].some((k) => v[k] !== null && v[k] !== undefined && !isNaN(v[k]));
        return hay ? { primaNeta: v.primaNeta ?? null, derechos: v.derechos ?? null, iva: v.iva ?? null, total: v.total ?? null } : null;
    }

    @api
    get tieneArchivo() { return !!this.archivo; }

    /**
     * Adjunta el documento del endoso al registro (la transacción del endoso).
     * @return true si se subió.
     */
    @api
    async subir(recordId) {
        if (!this.archivo || !recordId) { return false; }
        const base64 = await new Promise((resolve, reject) => {
            const lector = new FileReader();
            lector.onload = () => resolve(String(lector.result).split(',')[1]);
            lector.onerror = () => reject(lector.error);
            lector.readAsDataURL(this.archivo);
        });
        await llamar('MovimientosColectivo.subirArchivo', { recordId, nombre: this.archivo.name, base64 }, subirArchivo);
        return true;
    }
}
