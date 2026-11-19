import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import obtenerPanel from '@salesforce/apex/OportunidadesPanelController.obtenerPanel';

// ============================================================
// CATÁLOGOS
// ============================================================
// Etapas reales del org (StageName) con su etiqueta y la clase de color del chip.
const ETAPAS = [
    { valor: 'Gestion Comercial', etiqueta: 'Gestión Comercial', clave: 'gestion' },
    { valor: 'En proceso de emision', etiqueta: 'En proceso de emisión', clave: 'emision' },
    { valor: 'Póliza', etiqueta: 'Póliza', clave: 'poliza' },
    { valor: 'Closed Won', etiqueta: 'Ganada', clave: 'ganada' },
    { valor: 'Closed Lost', etiqueta: 'Perdida', clave: 'perdida' }
];
const ETAPAS_CERRADAS = ['Closed Won', 'Closed Lost'];
// Ramo (Ramo__c) → iniciales, etiqueta y clase de color del ícono.
const RAMOS = {
    Automoviles: { ini: 'A', etiqueta: 'Autos', clave: 'autos' },
    GMM: { ini: 'GM', etiqueta: 'Gastos Médicos', clave: 'gmm' },
    Danos: { ini: 'D', etiqueta: 'Daños', clave: 'danos' },
    Vida: { ini: 'V', etiqueta: 'Vida', clave: 'vida' },
    Viajes: { ini: 'VJ', etiqueta: 'Viajes', clave: 'viajes' },
    Mascotas: { ini: 'M', etiqueta: 'Mascotas', clave: 'mascotas' },
    Vision: { ini: 'VS', etiqueta: 'Visión', clave: 'otro' },
    Empresarial: { ini: 'E', etiqueta: 'Empresarial', clave: 'otro' },
    RC: { ini: 'RC', etiqueta: 'Responsabilidad Civil', clave: 'otro' }
};
// Saludo del encabezado: una frase distinta cada día (rota por día del año, igual para todos ese día). {n} es el
// nombre del usuario; sin nombre se quita ", {n}".
const SALUDOS = [
    '¡Vamos por el cierre, {n}!',
    '¡Hoy es un gran día para cerrar, {n}!',
    '¡A convertir oportunidades en pólizas, {n}!',
    '¡Cada llamada cuenta, {n}!',
    '¡Tus clientes te esperan, {n}!',
    '¡Un cierre más y vas que vuelas, {n}!',
    '¡Hoy se protege a alguien más, {n}!',
    '¡Paso a paso hacia la meta, {n}!',
    '¡Dale seguimiento y cierra, {n}!',
    '¡Que hoy sea día de pólizas, {n}!',
    '¡La constancia gana ventas, {n}!',
    '¡Vamos con todo, {n}!',
    '¡Tu próxima póliza está aquí, {n}!',
    '¡A cerrar con confianza, {n}!',
    '¡Hoy suma una póliza más, {n}!',
    '¡El seguimiento hace la diferencia, {n}!',
    '¡Convierte cada cotización en póliza, {n}!',
    '¡Arriba ese embudo, {n}!',
    '¡Hoy es día de buenas noticias, {n}!',
    '¡Cada cliente protegido cuenta, {n}!',
    '¡A romperla hoy, {n}!',
    '¡Tu meta está más cerca, {n}!',
    '¡Una oportunidad a la vez, {n}!',
    '¡Hoy cerramos fuerte, {n}!',
    '¡El que persevera, cierra, {n}!',
    '¡Vamos por esas firmas, {n}!',
    '¡Haz que hoy cuente, {n}!',
    '¡Tus clientes confían en ti, {n}!',
    '¡A llenar el tablero de pólizas, {n}!',
    '¡Hoy es tu día, {n}!',
    '¡Sigue sumando cierres, {n}!'
];
// Valor del filtro de agente para las oportunidades sin Producer.
const SIN_AGENTE = 'ninguno';
const TIPOS_VENTA = {
    New_Business: 'Nueva',
    Internal_Renewal: 'Renovación interna',
    External_Renewal: 'Renovación externa'
};
const FILTROS_TIPO = [
    { valor: 'todas', etiqueta: 'Todas' },
    { valor: 'Individual', etiqueta: 'Individual' },
    { valor: 'Colectiva', etiqueta: 'Empresarial' }
];
// Colores de avatar (texto blanco con contraste AA).
const COLORES_AVATAR = ['#1E63E9', '#BE185D', '#0B2559', '#6D28D9', '#0F7A47', '#C2410C', '#0369A1'];
const TAMANO_PAGINA = 30;
const DIA_MS = 86400000;
// Pestaña (Lightning App Page) donde vive el componente opportunityCreator.
const PESTANA_CREAR_OPORTUNIDAD = 'Crear_Oportunidad';

export default class OportunidadesPanel extends NavigationMixin(LightningElement) {
    /** Meta mensual de pólizas emitidas por el usuario (configurable en el App Builder). */
    @api metaMensual = 10;
    /** Días hacia adelante para el aviso de oportunidades por vencer. */
    @api diasPorVencer = 45;
    // Dentro de Crear Oportunidad: los botones avisan con el evento «accion» en lugar de navegar a la pestaña.
    @api incrustado = false;

    datos;
    cargando = true;
    error;
    busqueda = '';
    filtroTipo = 'todas';
    filtroAgente = '';
    soloVencidas = false;
    etapaFiltro = null;
    vista = 'lista';
    limite = TAMANO_PAGINA;

    connectedCallback() {
        this.cargar();
    }

    async cargar() {
        this.cargando = true;
        this.error = null;
        try {
            this.datos = await obtenerPanel();
        } catch (e) {
            this.error = (e && e.body && e.body.message) || (e && e.message) || 'Error desconocido';
            this.datos = null;
        } finally {
            this.cargando = false;
        }
    }

    handleRecargar() {
        this.cargar();
    }

    // ============================================================
    // UTILIDADES
    // ============================================================
    get meta() {
        const n = parseInt(this.metaMensual, 10);
        return n > 0 ? n : 10;
    }
    get horizonte() {
        const n = parseInt(this.diasPorVencer, 10);
        return n > 0 ? n : 45;
    }
    hoyFecha() {
        const base = this.datos && this.datos.hoy ? this.parseFecha(this.datos.hoy) : null;
        if (base) { return base; }
        const h = new Date();
        return new Date(h.getFullYear(), h.getMonth(), h.getDate());
    }
    parseFecha(iso) {
        if (!iso) { return null; }
        const p = String(iso).substring(0, 10).split('-');
        if (p.length !== 3) { return null; }
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    }
    formatoFecha(iso) {
        const d = this.parseFecha(iso);
        if (!d) { return 'Sin fecha'; }
        return d.toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' });
    }
    dinero(n) {
        const v = Number(n) || 0;
        return '$' + v.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    dineroCorto(n) {
        const v = Number(n) || 0;
        if (v >= 1e6) { return '$' + (v / 1e6).toLocaleString('es-MX', { maximumFractionDigits: 1 }) + ' M'; }
        if (v >= 1e3) { return '$' + Math.round(v / 1e3).toLocaleString('es-MX') + ' mil'; }
        return this.dinero(v);
    }
    iniciales(nombre) {
        const partes = String(nombre || '?').trim().split(/\s+/).filter(Boolean);
        if (!partes.length) { return '?'; }
        const a = partes[0].charAt(0);
        const b = partes.length > 1 ? partes[partes.length - 1].charAt(0) : '';
        return (a + b).toUpperCase();
    }
    colorAvatar(id) {
        const s = String(id || '');
        let h = 0;
        for (let i = 0; i < s.length; i++) { h = (h * 31 + s.charCodeAt(i)) % 997; }
        return COLORES_AVATAR[h % COLORES_AVATAR.length];
    }
    etapaDe(valor) {
        return ETAPAS.find((e) => e.valor === valor) || { valor, etiqueta: valor || 'Sin etapa', clave: 'otra' };
    }
    ramoDe(valor) {
        return RAMOS[valor] || { ini: valor ? valor.substring(0, 2).toUpperCase() : '?', etiqueta: valor || 'Sin ramo', clave: 'otro' };
    }
    plural(n, uno, varios) {
        return `${n} ${n === 1 ? uno : varios}`;
    }

    // ============================================================
    // OPORTUNIDADES ENRIQUECIDAS
    // ============================================================
    get todas() {
        if (!this.datos || !this.datos.oportunidades) { return []; }
        const hoy = this.hoyFecha();
        return this.datos.oportunidades.map((o) => {
            const etapa = this.etapaDe(o.etapa);
            const ramo = this.ramoDe(o.ramo);
            const cerrada = ETAPAS_CERRADAS.includes(o.etapa);
            const cierre = this.parseFecha(o.fechaCierre);
            const dias = cierre ? Math.round((cierre - hoy) / DIA_MS) : null;
            const vencida = !cerrada && dias !== null && dias < 0;
            let venceTexto;
            let venceClave;
            if (o.etapa === 'Closed Won') { venceTexto = '¡Cerrada!'; venceClave = 'ganada'; }
            else if (o.etapa === 'Closed Lost') { venceTexto = 'Cerrada'; venceClave = 'neutro'; }
            else if (dias === null) { venceTexto = 'Sin fecha de cierre'; venceClave = 'neutro'; }
            else if (dias < 0) { venceTexto = `Vencida hace ${this.plural(-dias, 'día', 'días')}`; venceClave = 'vencida'; }
            else if (dias === 0) { venceTexto = 'Vence hoy'; venceClave = 'pronto'; }
            else if (dias <= 30) { venceTexto = `${this.plural(dias, 'día restante', 'días restantes')}`; venceClave = 'pronto'; }
            else { venceTexto = `${dias} días restantes`; venceClave = 'aTiempo'; }
            const cot = o.cotizaciones || 0;
            const tipo = o.tipoContratacion === 'Colectiva' ? 'Empresarial' : 'Individual';
            const nombre = o.nombre || o.cuenta || 'Sin nombre';
            const sub = [
                tipo,
                cot ? this.plural(cot, 'cotización', 'cotizaciones') : 'Sin cotizaciones'
            ].join(' · ');
            const tipoVenta = TIPOS_VENTA[o.tipoVenta] || o.tipoVenta || 'Sin tipo';
            return {
                id: o.id,
                nombre,
                sub,
                tipo,
                etapaValor: o.etapa,
                etapa: etapa.etiqueta,
                puedeCorreo: o.etapa === 'Gestion Comercial' || o.etapa === 'En proceso de emision',
                correoAria: `Enviar correo de ${nombre}`,
                archivosAria: `Ver archivos de ${nombre}`,
                etapaClase: `etapa-tag etapa-tag-${etapa.clave}`,
                ramoIni: ramo.ini,
                ramoEtiqueta: ramo.etiqueta,
                ramoClase: `ramo ramo-${ramo.clave}`,
                ramoClaseChica: `ramo ramo-chico ramo-${ramo.clave}`,
                prima: Number(o.prima) || 0,
                primaTexto: this.dinero(o.prima),
                detalleVenta: `${tipoVenta} · ${o.canal || 'Sin canal'}`,
                cuenta: o.cuenta || '—',
                tipoVenta,
                canal: o.canal || '—',
                cierreTexto: this.formatoFecha(o.fechaCierre),
                creadaMs: o.creada ? new Date(o.creada).getTime() : 0,
                creadaTexto: o.creada
                    ? new Date(o.creada).toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' })
                    : '—',
                dias,
                cerrada,
                vencida,
                venceTexto,
                venceClase: `vence vence-${venceClave}`,
                propietarioId: o.propietarioId,
                propietario: o.propietario || 'Sin propietario',
                propietarioIni: this.iniciales(o.propietario),
                propietarioEstilo: `background-color: ${this.colorAvatar(o.propietarioId)};`,
                propietarioAria: `Propietario: ${o.propietario || 'sin propietario'}`,
                agenteId: o.agenteId || null,
                agente: o.agente || 'Sin agente',
                agenteIni: o.agente ? this.iniciales(o.agente) : '—',
                abrirAria: `Abrir ${nombre} en Crear Oportunidad`,
                cotizaciones: cot,
                busqueda: [nombre, o.cuenta, o.propietario, o.agente, ramo.etiqueta, etapa.etiqueta].join(' ').toLowerCase()
            };
        }).sort((x, y) => y.creadaMs - x.creadaMs);   // más reciente primero
    }
    get abiertas() {
        return this.todas.filter((o) => !o.cerrada);
    }
    // Oportunidades con filtros de tipo, vencidas y búsqueda (sin el filtro de etapa: alimentan el embudo).
    get filtradas() {
        const q = (this.busqueda || '').trim().toLowerCase();
        return this.todas.filter((o) => {
            if (this.filtroTipo !== 'todas' && o.tipo !== this.filtroTipo) { return false; }
            if (this.soloVencidas && !o.vencida) { return false; }
            if (this.filtroAgente === SIN_AGENTE && o.agenteId) { return false; }
            if (this.filtroAgente && this.filtroAgente !== SIN_AGENTE && o.agenteId !== this.filtroAgente) { return false; }
            if (q && !o.busqueda.includes(q)) { return false; }
            return true;
        });
    }
    get listadas() {
        const f = this.filtradas;
        return this.etapaFiltro ? f.filter((o) => o.etapaValor === this.etapaFiltro) : f;
    }

    // ============================================================
    // HERO Y METAS
    // ============================================================
    get hayDatos() { return !this.cargando && !this.error && !!this.datos; }
    get saludo() {
        const n = this.datos && this.datos.nombreUsuario ? this.datos.nombreUsuario : '';
        const hoy = new Date();
        const diaDelAnio = Math.floor((Date.UTC(hoy.getFullYear(), hoy.getMonth(), hoy.getDate())
            - Date.UTC(hoy.getFullYear(), 0, 0)) / 86400000);
        const frase = SALUDOS[diaDelAnio % SALUDOS.length];
        return n ? frase.replace('{n}', n) : frase.replace(', {n}', '');
    }
    get porVencer() {
        const uid = this.datos ? this.datos.usuarioId : null;
        return this.abiertas.filter((o) => o.propietarioId === uid && o.dias !== null && o.dias >= 0 && o.dias <= this.horizonte).length;
    }
    get porVencerTexto() {
        return this.plural(this.porVencer, 'oportunidad tuya', 'oportunidades tuyas');
    }
    get horizonteTexto() {
        return `${this.horizonte} días`;
    }
    get totalAbiertas() {
        return this.abiertas.length.toLocaleString('es-MX');
    }
    get desgloseAbiertas() {
        const ind = this.abiertas.filter((o) => o.tipo === 'Individual').length;
        const col = this.abiertas.length - ind;
        return `${this.plural(ind, 'individual', 'individuales')} · ${this.plural(col, 'empresarial', 'empresariales')}`;
    }
    get valorTotal() {
        return this.dineroCorto(this.abiertas.reduce((s, o) => s + o.prima, 0));
    }
    get polizasMes() {
        return this.datos ? this.datos.polizasMesUsuario || 0 : 0;
    }
    get metaTexto() {
        return `${this.polizasMes} de ${this.meta}`;
    }
    get metaPorcentaje() {
        return Math.min(100, Math.round((this.polizasMes / this.meta) * 100));
    }
    get metaBarraEstilo() {
        return `width: ${this.metaPorcentaje}%;`;
    }
    get metaMensaje() {
        const faltan = this.meta - this.polizasMes;
        if (faltan <= 0) { return '¡Meta cumplida! Cada póliza extra suma al ranking.'; }
        return `Te ${faltan === 1 ? 'falta' : 'faltan'} ${this.plural(faltan, 'póliza', 'pólizas')} para la meta del mes.`;
    }
    get metaAria() {
        return `Meta del mes: ${this.polizasMes} de ${this.meta} pólizas (${this.metaPorcentaje}%)`;
    }

    // ============================================================
    // LOGROS
    // ============================================================
    get racha() {
        return this.datos ? this.datos.rachaDias || 0 : 0;
    }
    get rachaTitulo() {
        return this.racha > 0 ? `Racha de ${this.plural(this.racha, 'día', 'días')}` : 'Sin racha activa';
    }
    get rachaTexto() {
        if (this.racha > 0) {
            return this.datos.polizasHoyUsuario > 0
                ? 'emitiendo al menos una póliza al día'
                : 'emite una póliza hoy para mantenerla';
        }
        return 'emite una póliza hoy para iniciar tu racha';
    }
    get rachaClase() {
        return this.racha > 0 ? 'logro-icono logro-racha activo' : 'logro-icono logro-racha';
    }
    get rey() {
        return this.datos ? this.datos.reyAutos : null;
    }
    get reyTexto() {
        const r = this.rey;
        if (!r) { return 'Aún nadie esta semana: ¡puede ser tuyo!'; }
        const pol = this.plural(r.autosSemana, 'póliza de autos', 'pólizas de autos');
        return r.esUsuarioActual ? `¡Eres tú! ${pol} esta semana` : `${r.nombre} · ${pol} esta semana`;
    }
    get misAutosSemana() {
        const uid = this.datos ? this.datos.usuarioId : null;
        const yo = (this.datos && this.datos.ranking ? this.datos.ranking : []).find((a) => a.usuarioId === uid);
        return yo ? yo.autosSemana || 0 : 0;
    }
    get siguienteLogro() {
        const faltanMeta = this.meta - this.polizasMes;
        if (faltanMeta > 0) {
            return `${this.plural(faltanMeta, 'póliza más', 'pólizas más')} para «Meta del mes»`;
        }
        const r = this.rey;
        if (!r || !r.esUsuarioActual) {
            const faltan = Math.max(1, (r ? r.autosSemana : 0) + 1 - this.misAutosSemana);
            return `${this.plural(faltan, 'póliza de autos más', 'pólizas de autos más')} para «Rey de Autos»`;
        }
        return `Emite mañana para llegar a ${this.plural(this.racha + 1, 'día', 'días')} de racha`;
    }

    // ============================================================
    // EMBUDO
    // ============================================================
    get embudo() {
        const f = this.filtradas;
        return ETAPAS.map((e) => {
            const os = f.filter((o) => o.etapaValor === e.valor);
            const suma = os.reduce((s, o) => s + o.prima, 0);
            const pct = f.length ? Math.round((os.length / f.length) * 100) : 0;
            const activa = this.etapaFiltro === e.valor;
            return {
                valor: e.valor,
                etiqueta: e.etiqueta,
                conteo: os.length,
                prima: `${this.dineroCorto(suma)} en prima`,
                clase: `etapa-card etapa-${e.clave}${activa ? ' activa' : ''}`,
                barraEstilo: `width: ${pct}%;`,
                presionado: activa ? 'true' : 'false',
                aria: `${e.etiqueta}: ${os.length} oportunidades, ${this.dineroCorto(suma)} en prima. ${activa ? 'Quitar filtro' : 'Filtrar por esta etapa'}`
            };
        });
    }
    handleEtapa(event) {
        const v = event.currentTarget.dataset.valor;
        this.etapaFiltro = this.etapaFiltro === v ? null : v;
        this.limite = TAMANO_PAGINA;
    }
    get etapaFiltroTexto() {
        return this.etapaFiltro ? this.etapaDe(this.etapaFiltro).etiqueta : '';
    }
    handleQuitarEtapa() {
        this.etapaFiltro = null;
    }

    // ============================================================
    // BARRA DE FILTROS
    // ============================================================
    get filtrosTipo() {
        return FILTROS_TIPO.map((t) => ({
            ...t,
            clase: this.filtroTipo === t.valor ? 'segmento activo' : 'segmento',
            presionado: this.filtroTipo === t.valor ? 'true' : 'false'
        }));
    }
    handleTipo(event) {
        this.filtroTipo = event.currentTarget.dataset.valor;
        this.limite = TAMANO_PAGINA;
    }
    handleBusqueda(event) {
        this.busqueda = event.target.value;
        this.limite = TAMANO_PAGINA;
    }
    // Filtro por agente (Producer): todos los agentes de la org, más "Sin agente".
    get opcionesAgente() {
        const lista = (this.datos && this.datos.agentes) || [];
        return [
            { valor: '', etiqueta: 'Todos los agentes', seleccionado: !this.filtroAgente },
            { valor: SIN_AGENTE, etiqueta: 'Sin agente', seleccionado: this.filtroAgente === SIN_AGENTE },
            ...lista.map((a) => ({ valor: a.id, etiqueta: a.nombre, seleccionado: this.filtroAgente === a.id }))
        ];
    }
    get agenteClase() {
        return this.filtroAgente ? 'selector-agente activo' : 'selector-agente';
    }
    handleAgente(event) {
        this.filtroAgente = event.target.value;
        this.limite = TAMANO_PAGINA;
    }
    handleVencidas() {
        this.soloVencidas = !this.soloVencidas;
        this.limite = TAMANO_PAGINA;
    }
    get vencidasClase() {
        return this.soloVencidas ? 'pill pill-toggle activo' : 'pill pill-toggle';
    }
    get vencidasPresionado() {
        return this.soloVencidas ? 'true' : 'false';
    }
    get esLista() { return this.vista === 'lista'; }
    get esTablero() { return this.vista === 'tablero'; }
    get listaClase() { return this.esLista ? 'segmento segmento-icono activo' : 'segmento segmento-icono'; }
    get tableroClase() { return this.esTablero ? 'segmento segmento-icono activo' : 'segmento segmento-icono'; }
    get listaPresionado() { return this.esLista ? 'true' : 'false'; }
    get tableroPresionado() { return this.esTablero ? 'true' : 'false'; }
    handleVistaLista() { this.vista = 'lista'; }
    handleVistaTablero() { this.vista = 'tablero'; }

    // ============================================================
    // LISTA Y TABLERO
    // ============================================================
    get filas() {
        return this.listadas.slice(0, this.limite);
    }
    get sinFilas() {
        return this.listadas.length === 0;
    }
    get hayMas() {
        return this.listadas.length > this.limite;
    }
    get pieTexto() {
        const total = this.listadas.length;
        const vis = Math.min(total, this.limite);
        return `Mostrando ${vis.toLocaleString('es-MX')} de ${this.plural(total, 'oportunidad', 'oportunidades')} (abiertas y movidas en los últimos 90 días)`;
    }
    handleMostrarMas() {
        this.limite += TAMANO_PAGINA;
    }
    get columnas() {
        const l = this.listadas;
        return ETAPAS.map((e) => {
            const os = l.filter((o) => o.etapaValor === e.valor);
            const suma = os.reduce((s, o) => s + o.prima, 0);
            return {
                valor: e.valor,
                etiqueta: e.etiqueta,
                conteo: os.length,
                prima: this.dineroCorto(suma),
                clase: `columna columna-${e.clave}`,
                badgeClase: `chip chip-${e.clave}`,
                tarjetas: os.slice(0, 25),
                hayMas: os.length > 25,
                masTexto: `y ${os.length - 25} más…`,
                vacia: os.length === 0
            };
        });
    }

    // ============================================================
    // RANKING, RESCATE Y TIP
    // ============================================================
    get ranking() {
        const lista = this.datos && this.datos.ranking ? this.datos.ranking : [];
        return lista.map((a, i) => ({
            ...a,
            lugar: i + 1,
            ini: this.iniciales(a.nombre),
            nombreCorto: (a.nombre || 'Sin nombre').split(/\s+/).slice(0, 2).join(' '),
            puntos: this.plural(a.polizasMes, 'póliza', 'pólizas'),
            avatarEstilo: `background-color: ${this.colorAvatar(a.usuarioId)};`,
            clase: `podio-lugar podio-${i + 1}${a.esUsuarioActual ? ' soy-yo' : ''}`,
            filaClase: a.esUsuarioActual ? 'ranking-fila soy-yo' : 'ranking-fila'
        }));
    }
    get hayRanking() {
        return this.ranking.length > 0;
    }
    // Podio en orden visual 2º, 1º, 3º.
    get podio() {
        const r = this.ranking.slice(0, 3);
        const orden = [r[1], r[0], r[2]].filter(Boolean);
        return orden;
    }
    get restoRanking() {
        return this.ranking.slice(3);
    }
    get hayRestoRanking() {
        return this.restoRanking.length > 0;
    }
    get urgentes() {
        return this.abiertas
            .filter((o) => o.etapaValor !== 'Póliza' && o.dias !== null && o.dias <= 7)
            .sort((a, b) => a.dias - b.dias)
            .slice(0, 4)
            .map((o) => ({
                ...o,
                urgenteTexto: `${o.venceTexto} · ${this.dineroCorto(o.prima)}`,
                retomarAria: `Retomar ${o.nombre}`
            }));
    }
    get hayUrgentes() {
        return this.urgentes.length > 0;
    }
    get totalVencidas() {
        return this.abiertas.filter((o) => o.vencida).length;
    }
    // Tip simple por reglas (sin IA externa).
    get tip() {
        const abiertas = this.abiertas;
        const comparar = abiertas
            .filter((o) => o.etapaValor === 'Gestion Comercial' && o.cotizaciones >= 2 && o.dias !== null && o.dias >= 0 && o.dias <= this.horizonte)
            .sort((a, b) => a.dias - b.dias)[0];
        if (comparar) {
            return {
                texto: `${comparar.nombre} tiene ${comparar.cotizaciones} cotizaciones y cierra en ${this.plural(comparar.dias, 'día', 'días')}. Mándale hoy el comparativo: las propuestas tempranas se cierran más fácil.`,
                boton: 'Abrir oportunidad',
                accion: 'abrir',
                id: comparar.id
            };
        }
        const vencidas = this.totalVencidas;
        if (vencidas > 0) {
            return {
                texto: `Tienes ${this.plural(vencidas, 'oportunidad vencida', 'oportunidades vencidas')} en esta vista. Actualiza su fecha de cierre o regístralas como perdidas para que tu embudo refleje la realidad.`,
                boton: this.soloVencidas ? 'Ver todas' : 'Ver vencidas',
                accion: 'vencidas'
            };
        }
        const sinCot = abiertas.find((o) => o.etapaValor === 'Gestion Comercial' && o.cotizaciones === 0);
        if (sinCot) {
            return {
                texto: `${sinCot.nombre} aún no tiene cotizaciones. Sube los PDFs de las aseguradoras y deja que la IA arme la oportunidad y el comparativo.`,
                boton: 'Crear desde PDFs',
                accion: 'pdf'
            };
        }
        return {
            texto: 'Revisa las oportunidades en proceso de emisión: cargar el PDF de la póliza a tiempo suma a tu meta y a tu racha.',
            boton: null,
            accion: null
        };
    }
    get tipTieneBoton() {
        return !!this.tip.boton;
    }
    handleTip() {
        const t = this.tip;
        if (t.accion === 'abrir') { this.navegarEditor(t.id); }
        else if (t.accion === 'vencidas') { this.handleVencidas(); }
        else if (t.accion === 'pdf') { this.handleCrearPdf(); }
    }

    // ============================================================
    // NAVEGACIÓN
    // ============================================================
    // «Nueva oportunidad»: abre la pestaña Crear Oportunidad directo en el formulario nuevo.
    handleNueva() {
        this.navegarCreador('nueva');
    }
    // «Crear desde PDFs con IA»: abre la misma pestaña en la vista de carga de PDFs.
    handleCrearPdf() {
        this.navegarCreador('pdf');
    }
    navegarCreador(accion) {
        if (this.incrustado) {
            this.dispatchEvent(new CustomEvent('accion', { detail: { accion } }));
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: PESTANA_CREAR_OPORTUNIDAD },
            // c__t cambia en cada clic para que la pestaña (que puede seguir abierta) vuelva a leer la acción.
            state: { c__accion: accion, c__t: String(Date.now()) }
        });
    }
    // Abre la oportunidad en el editor de Crear Oportunidad (mismo flujo que la lista de ese componente).
    navegarEditor(id) {
        if (!id) { return; }
        if (this.incrustado) {
            this.dispatchEvent(new CustomEvent('accion', { detail: { accion: 'editar', id } }));
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: PESTANA_CREAR_OPORTUNIDAD },
            state: { c__opportunityId: id }
        });
    }
    // Solo dentro de Crear Oportunidad: enviar el correo de la oportunidad y ver sus archivos (modales de ese componente).
    handleCorreo(event) {
        this.dispatchEvent(new CustomEvent('accion', { detail: { accion: 'correo', id: event.currentTarget.dataset.id } }));
    }
    handleArchivos(event) {
        const { id, name } = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('accion', { detail: { accion: 'archivos', id, nombre: name } }));
    }
    handleAbrirEditor(event) {
        this.navegarEditor(event.currentTarget.dataset.id);
    }
    // Abre el registro estándar de la oportunidad.
    handleAbrirRegistro(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) { return; }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: 'Opportunity', actionName: 'view' }
        });
    }
}
