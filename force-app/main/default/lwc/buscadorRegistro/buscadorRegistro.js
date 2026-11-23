// buscadorRegistro/buscadorRegistro.js
// Lista desplegable en la que también se puede escribir para buscar (nombre, certificado, serie, inciso…). Se usa en
// c-portal-solicitudes igual que un lightning-combobox: value, options [{ label, value }], evento change con detail.value
// y reportValidity().
import { LightningElement, api } from 'lwc';
import { fold } from 'c/lectorArchivos';

// Opciones que se pintan a la vez; con más, se pide escribir para acotar.
const MAX_OPCIONES = 200;

export default class BuscadorRegistro extends LightningElement {
    @api label;
    @api placeholder = '';
    @api required = false;
    @api disabled = false;
    abierto = false;
    // Texto que se está escribiendo; null = se muestra la opción elegida.
    texto = null;
    resaltada = -1;
    error = '';
    _value = '';
    _options = [];

    @api
    get value() { return this._value; }
    set value(v) {
        const nuevo = v || '';
        if (nuevo === this._value) { return; }
        this._value = nuevo;
        this.texto = null;
        if (nuevo) { this.error = ''; }
    }
    @api
    get options() { return this._options; }
    set options(v) { this._options = Array.isArray(v) ? v : []; }

    @api
    checkValidity() { return !this.required || !!this.seleccion; }
    @api
    reportValidity() {
        const ok = this.checkValidity();
        this.error = ok ? '' : (this.texto && this.texto.trim() ? 'Elige una opción de la lista.' : 'Completa este campo.');
        return ok;
    }
    @api
    focus() { this.campo.focus(); }

    get campo() { return this.template.querySelector('input'); }
    get seleccion() { return this._options.find((o) => o.value === this._value); }
    get textoVisible() { return this.texto !== null ? this.texto : ((this.seleccion && this.seleccion.label) || ''); }
    get cerrado() { return !this.abierto; }
    get expandido() { return String(this.abierto); }
    get invalido() { return String(!!this.error); }
    get claseCampo() { return 'campo' + (this.error ? ' campo_error' : ''); }
    get limpiable() { return !this.disabled && !!this.textoVisible; }
    // Todas las palabras escritas, en cualquier orden y sin importar acentos ni mayúsculas.
    get coincidencias() {
        const palabras = fold(this.texto || '').split(/\s+/).filter((p) => p);
        if (!palabras.length) { return this._options; }
        return this._options.filter((o) => {
            const t = fold(o.label);
            return palabras.every((p) => t.includes(p));
        });
    }
    get visibles() { return this.coincidencias.slice(0, MAX_OPCIONES); }
    get opciones() {
        return this.visibles.map((o, i) => ({
            key: o.value, i, label: o.label,
            clase: 'opcion' + (i === this.resaltada ? ' opcion_activa' : '') + (o.value === this._value ? ' opcion_elegida' : ''),
            elegida: String(o.value === this._value)
        }));
    }
    get hayOpciones() { return this.coincidencias.length > 0; }
    get textoVacio() { return this._options.length ? 'No hay resultados con esa búsqueda.' : 'No hay registros para elegir.'; }
    get textoMas() {
        const n = this.coincidencias.length - MAX_OPCIONES;
        return n > 0 ? `y ${n} más: escribe para acotar la búsqueda` : '';
    }

    abrir() {
        if (this.disabled || this.abierto) { return; }
        this.abierto = true;
        this.resaltada = this.texto ? 0 : this.visibles.findIndex((o) => o.value === this._value);
        this.ver();
    }
    cerrar() {
        this.abierto = false;
        this.resaltada = -1;
    }
    handleFoco() {
        // Con algo elegido se selecciona el texto, para escribir encima.
        if (this.seleccion && this.texto === null) { this.campo.select(); }
        this.abrir();
    }
    handleEscribir(e) {
        e.stopPropagation();
        this.texto = e.target.value;
        this.error = '';
        this.abierto = true;
        this.resaltada = this.texto.trim() && this.hayOpciones ? 0 : -1;
        // Al cambiar el texto deja de haber una opción elegida.
        if (this._value) { this.elegir('', true); }
    }
    // El cambio nativo del campo no sale del componente (solo el de la opción elegida).
    handleCambioNativo(e) { e.stopPropagation(); }
    handleSalir() {
        this.cerrar();
        // Texto que deja una sola opción: se toma esa.
        if (this.texto !== null && this.texto.trim() && this.coincidencias.length === 1) { this.elegir(this.coincidencias[0].value); }
        else if (this.texto !== null && !this.texto.trim()) { this.texto = null; }
        this.reportValidity();
    }
    // El clic en la lista no le quita el foco al campo.
    handleSostener(e) { e.preventDefault(); }
    handleFlecha(e) {
        e.preventDefault();
        if (this.abierto) { this.cerrar(); return; }
        this.campo.focus();
        this.abrir();
    }
    handleLimpiar(e) {
        e.preventDefault();
        this.texto = '';
        this.elegir('', true);
        this.campo.focus();
        this.abierto = true;
        this.resaltada = -1;
    }
    handleOpcion(e) {
        this.elegir(this.visibles[Number(e.currentTarget.dataset.i)].value);
        this.cerrar();
    }
    handleTecla(e) {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            if (!this.abierto) { this.abrir(); return; }
            const n = this.visibles.length;
            if (!n) { return; }
            this.resaltada = e.key === 'ArrowDown' ? (this.resaltada + 1) % n : (this.resaltada <= 0 ? n : this.resaltada) - 1;
            this.ver();
        } else if (e.key === 'Enter') {
            if (!this.abierto) { return; }
            e.preventDefault();
            const o = this.visibles[this.resaltada];
            if (o) { this.elegir(o.value); this.cerrar(); }
        } else if (e.key === 'Escape' && this.abierto) {
            e.stopPropagation();
            this.cerrar();
        }
    }
    elegir(valor, conservarTexto) {
        if (!conservarTexto) { this.texto = null; }
        this._value = valor;
        if (valor) { this.error = ''; }
        this.dispatchEvent(new CustomEvent('change', { detail: { value: valor } }));
    }
    // La opción resaltada siempre a la vista.
    ver() {
        Promise.resolve().then(() => {
            const el = this.template.querySelector('.opcion_activa');
            if (el) { el.scrollIntoView({ block: 'nearest' }); }
        });
    }
}
