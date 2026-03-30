import { LightningElement, wire } from 'lwc';
import obtenerProyeccionCobranza from '@salesforce/apex/CobranzaPolizaController.obtenerProyeccionCobranza';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import POLIZA_OBJECT from '@salesforce/schema/Polizas__c';
import ESTATUS_POLIZA_FIELD from '@salesforce/schema/Polizas__c.Estatus__c';
import ASEGURADORA_FIELD from '@salesforce/schema/Polizas__c.Aseguradora__c';

export default class CobranzaPolizaDashboard extends LightningElement {
    //Data desde apex
    dataOriginalMensual = [];
    dataOriginalMatriz = [];

    //Data filtrada para ambas vistas
    dataFiltradaMensual = [];
    dataFiltradaMatriz = [];
    
    //Data para construir las vistas
    dataMensual = [];
    matrizData = [];
    
    //Data para la paginación
    dataMensualPaginada = [];
    dataMatrizPaginada = [];
    
    //Variables de estado de la interfaz de usuario
    modoVista = 'mensual';
    isLoading = false;
    
    //Variables para el control de la petición a apex
    currentRequestIdMensual = 0;
    currentRequestIdMatriz = 0;

    //Variables para los filtros que no llaman a apex
    filtroPolizaId = null;
    filtroAseguradoId = null;
    filtroAseguradora = '';
    filtroEstatusPoliza = '';
    filtroEstatusRecibo = '';
    
    //Variables para los filtros que sí llaman a apex
    cantidadMeses = '6';
    mesSeleccionado;
    anioSeleccionado;
    anios = [];

    //Variables de paginación
    paginaActualMensual = 1;
    tamanoPaginaMensual = '10';
    paginaActualMatriz = 1;
    tamanoPaginaMatriz = '10';


    //Variables de configuración de matriz
    mesesMatriz = [];
    totalesPorMes = {};

    //Variables de opciones de filtros que no llaman a apex
    aseguradorasOptions = [];
    estatusPolizaOptions = [];
    
    estatusReciboOptions = [
        { label: 'Todos', value: '' },
        { label: 'Pagado', value: 'Pagado' },
        { label: 'Pendiente', value: 'Pendiente' },
        { label: 'Cancelado', value: 'Cancelado' },
        { label: 'Vencida', value: 'Vencida' },
        { label: 'Pagado con pendiente', value: '__MIXTO__' }
    ];

    //Variables de opciones de filtros que sí llaman a apex
    meses = [
        { label: 'Enero', value: '0' }, { label: 'Febrero', value: '1' },
        { label: 'Marzo', value: '2' }, { label: 'Abril', value: '3' },
        { label: 'Mayo', value: '4' }, { label: 'Junio', value: '5' },
        { label: 'Julio', value: '6' }, { label: 'Agosto', value: '7' },
        { label: 'Septiembre', value: '8' }, { label: 'Octubre', value: '9' },
        { label: 'Noviembre', value: '10' }, { label: 'Diciembre', value: '11' }
    ];

    opcionesMeses = [
        { label: '1 mes', value: '1' },
        { label: '2 meses', value: '2' },
        { label: '3 meses', value: '3' },
        { label: '4 meses', value: '4' },
        { label: '5 meses', value: '5' },
        { label: '6 meses', value: '6' },
        { label: '7 meses', value: '7' },
        { label: '8 meses', value: '8' },
        { label: '9 meses', value: '9' },
        { label: '10 meses', value: '10' },
        { label: '11 meses', value: '11' },
        { label: '12 meses', value: '12' }
    ];
    
    //Opciones de Paginación
    opcionesTamano = [
        { label: '5 por página', value: '5' },
        { label: '10 por página', value: '10' },
        { label: '20 por página', value: '20' },
        { label: '50 por página', value: '50' }
    ];
    
    //Columnas tabla mensual
    columnsMensual = [
        { 
            label: 'Póliza', 
            fieldName: 'numeroPoliza',
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        { 
            label: 'Asegurado', 
            fieldName: 'aseguradoNombre',
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        { 
            label: 'Aseguradora', 
            fieldName: 'aseguradora',
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        { 
            label: 'Forma de Pago', 
            fieldName: 'formaPago',
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        { 
            label: 'Estatus Póliza', 
            fieldName: 'estatusPoliza',
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        {
            label: 'Fecha Esperada Pago',
            fieldName: 'fechaEsperadaPago',
            type: 'date-local',
            typeAttributes: {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            },
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        {
            label: 'Fecha Último Pago',
            fieldName: 'fechaUltimoPago',
            type: 'date-local',
            typeAttributes: {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            },
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        { 
            label: 'Estatus Recibo', 
            fieldName: 'estatusRecibo',
            cellAttributes: { class: { fieldName: 'rowClass' } }
        },
        {
            label: 'Monto',
            fieldName: 'monto',
            type: 'currency',
            typeAttributes: {
                currencyCode: 'MXN',
                minimumFractionDigits: 0,
                maximumFractionDigits: 0
            },
            cellAttributes: {
                class: { fieldName: 'rowClass' },
                style: { fieldName: 'styleMontoMensual' }
            }
        },
        {
            type: 'button-icon',
            initialWidth: 60,
            typeAttributes: {
                iconName: 'utility:preview',
                name: 'detalles',
                title: 'Ver detalles',
                alternativeText: 'Ver detalles',
                variant: 'border'
            }
        }
    ];

    //Métodos inicializadores y lifecycle
    @wire(getObjectInfo, { objectApiName: POLIZA_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: ESTATUS_POLIZA_FIELD
    })
    wiredEstatusPolizaPicklist({ data, error }) {
        if (data) {
            this.estatusPolizaOptions = [
                { label: 'Todos', value: '' },
                ...data.values.map(v => ({
                    label: v.label,
                    value: v.value
                }))
            ];
        } else if (error) {
            console.error('Error cargando estatus poliza picklist', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: ASEGURADORA_FIELD
    })
    wiredAseguradoraPicklist({ data, error }) {
        if (data) {
            this.aseguradorasOptions = [
                { label: 'Todas', value: '' },
                ...data.values.map(v => ({
                    label: v.label,
                    value: v.value
                }))
            ];
        } else if (error) {
            console.error('Error cargando aseguradoras picklist', error);
        }
    }

    connectedCallback() {
        const hoy = new Date();
        this.mesSeleccionado = hoy.getMonth().toString();
        this.anioSeleccionado = hoy.getFullYear().toString();
        this.inicializarAnios();
        this.handleBuscar();
    }

    inicializarAnios() {
        const base = new Date().getFullYear();
        for (let i = -1; i <= 1; i++) {
            this.anios.push({ label: (base + i).toString(), value: (base + i).toString() });
        }
    }

    //Métodos handlers de la interfaz de usuario (handlers de botones y acciones)
    setVistaMensual() {
        this.modoVista = 'mensual';
    }
    
    setVistaMatriz() {
        this.modoVista = 'matriz';
    }
    
    handleBuscar() {
        this.buscarMensual();
        this.buscarMatriz();
    }

    irAnterior() {
        if (this.esMensual && this.paginaActualMensual > 1) {
            this.paginaActualMensual--;
            this.actualizarPaginacionMensual();
        }

        if (this.esMatriz && this.paginaActualMatriz > 1) {
            this.paginaActualMatriz--;
            this.actualizarPaginacionMatriz();
        }
    }

    irSiguiente() {
        if (this.esMensual) {
            const total = Math.ceil(this.dataMensual.length / parseInt(this.tamanoPaginaMensual, 10));

            if (this.paginaActualMensual < total) {
                this.paginaActualMensual++;
                this.actualizarPaginacionMensual();
            }
        }

        if (this.esMatriz) {
            const total = Math.ceil(this.matrizData.length / parseInt(this.tamanoPaginaMatriz, 10));
            if (this.paginaActualMatriz < total) {
                this.paginaActualMatriz++;
                this.actualizarPaginacionMatriz();
            }
        }
    }

    handleTamanoChange(event) {
        if (this.esMensual) {
            this.tamanoPaginaMensual = event.detail.value;
            this.paginaActualMensual = 1;
            this.actualizarPaginacionMensual();
        } else {
            this.tamanoPaginaMatriz = event.detail.value;
            this.paginaActualMatriz = 1;
            this.actualizarPaginacionMatriz();
        }
    }

    //Métodos orquestadores
    buscarMensual() {
        const requestId = ++this.currentRequestIdMensual;
        
        const fechaDesde = new Date(
            parseInt(this.anioSeleccionado),
            parseInt(this.mesSeleccionado),
            1
        );
        
        const fechaHasta = new Date(
            fechaDesde.getFullYear(),
            fechaDesde.getMonth() + 1,
            0
        );
        
        this.isLoading = true;
        
        obtenerProyeccionCobranza({
            fechaDesde: this.formatDate(fechaDesde),
            fechaHasta: this.formatDate(fechaHasta)
        })
        .then(res => {
            
            if (requestId !== this.currentRequestIdMensual) {
                return;
            }
            
            this.dataOriginalMensual = (res || []).map(r => ({
                ...r,
                fechaEsperadaPago: this.normalizarFechaISO(r.fechaEsperadaPago),
                fechaUltimoPago: this.normalizarFechaISO(r.fechaUltimoPago)
            }));
            this.dataFiltradaMensual = this.aplicarFiltros(this.dataOriginalMensual);
            this.construirVistaMensual();
            
            this.paginaActualMensual = 1;
            this.actualizarPaginacionMensual();
        })
        .finally(() => {
            if (requestId === this.currentRequestIdMensual) {
                this.isLoading = false;
            }
        });
    }

    buscarMatriz() {
        const requestId = ++this.currentRequestIdMatriz;

        const meses = parseInt(this.cantidadMeses, 10);

        const fechaDesde = new Date(
            parseInt(this.anioSeleccionado),
            parseInt(this.mesSeleccionado),
            1
        );

        const fechaHasta = new Date(
            fechaDesde.getFullYear(),
            fechaDesde.getMonth() + meses,
            0
        );

        this.isLoading = true;

        obtenerProyeccionCobranza({
            fechaDesde: this.formatDate(fechaDesde),
            fechaHasta: this.formatDate(fechaHasta)
        })
        .then(res => {

            if (requestId !== this.currentRequestIdMatriz) {
                return;
            }

            this.dataOriginalMatriz = (res || []).map(r => ({
                ...r,
                fechaEsperadaPago: this.normalizarFechaISO(r.fechaEsperadaPago),
                fechaUltimoPago: this.normalizarFechaISO(r.fechaUltimoPago)
            }));
            this.dataFiltradaMatriz = this.aplicarFiltros(this.dataOriginalMatriz);

            this.construirMatriz(this.dataFiltradaMatriz, fechaDesde);
        })
        .finally(() => {
            if (requestId === this.currentRequestIdMatriz) {
                this.isLoading = false;
            }
        });
    }

    
    recalcularVista() {
        const dataFiltradaMensual = this.aplicarFiltros(this.dataOriginalMensual);
        this.dataFiltradaMensual = dataFiltradaMensual;
        
        this.construirVistaMensual();
        this.paginaActualMensual = 1;
        this.actualizarPaginacionMensual();
        
        const dataFiltradaMatriz = this.aplicarFiltros(this.dataOriginalMatriz);
        
        const fechaInicio = new Date(
            parseInt(this.anioSeleccionado),
            parseInt(this.mesSeleccionado),
            1
        );
        
        this.construirMatriz(dataFiltradaMatriz, fechaInicio);
    }

    //Métodos builders de vista
    construirVistaMensual() {
        const rango = this.generarRangoMensual(
            parseInt(this.mesSeleccionado),
            parseInt(this.anioSeleccionado)
        );

        const desde = this.parseDateLocal(rango.fechaDesde);
        const hasta = this.parseDateLocal(rango.fechaHasta);

        this.dataMensual = this.dataFiltradaMensual
            .filter(item => {
                if (!item.fechaEsperadaPago) return false;

                const fechaPago = this.parseDateLocal(item.fechaEsperadaPago);
                const dentroRango = fechaPago >= desde && fechaPago <= hasta;

                let cumpleEstatus = true;
                if (this.filtroEstatusRecibo) {
                    if (this.filtroEstatusRecibo === '__MIXTO__') {
                        cumpleEstatus = !!item.tieneMontoPendiente;
                    } else {
                        cumpleEstatus = item.estatusRecibo === this.filtroEstatusRecibo;
                    }
                }

                return dentroRango && cumpleEstatus;
            })
            .map(item => {
                let rowClass = '';
                let styleMontoMensual = '';

                if (item.esPolizaInactiva) {
                    rowClass = 'slds-text-color_destructive';
                }

                // PRIORIDAD 1: cruce nueva vigencia (púrpura)
                if (item.tieneMezclaVigencia) {
                    rowClass += ' slds-theme_alert-texture';
                    styleMontoMensual = 'color:#6b21a8; font-weight:800;';
                }
                // PRIORIDAD 2: arrastre (magenta)
                else if (item.tieneArrastre) {
                    styleMontoMensual = 'color:#a1005e; font-weight:900;';
                }
                // PRIORIDAD 3: pagado + pendiente (azul)
                else if (item.esPagoReal && item.estaPagado && item.tieneMontoPendiente) {
                    styleMontoMensual = 'color:#1b5297; font-weight:800;';
                }
                // PRIORIDAD 4: nueva vigencia normal (naranja)
                else if (item.esNuevaVigencia) {
                    rowClass += ' slds-theme_alert-texture';
                    styleMontoMensual = 'color:#dd7a01; font-weight:700;';
                }
                // Pagado (verde)
                else if (item.esPagoReal && item.estaPagado) {
                    styleMontoMensual = 'color:#2e844a; font-weight:700;';
                }
                // Pendiente existente (rojo)
                else if (item.esPagoReal && !item.estaPagado) {
                    styleMontoMensual = 'color:#ba0517; font-weight:700;';
                }

                return {
                    ...item,
                    rowKey: `${item.polizaId}-${item.fechaEsperadaPago}`,
                    rowClass: rowClass.trim(),
                    styleMontoMensual
                };
            });
    }

    construirMatriz(data, fechaInicio) {

        this.matrizData = [];
        this.mesesMatriz = [];
        this.totalesPorMes = {};

        const meses = parseInt(this.cantidadMeses, 10);

        const nuevosMeses = [];
        const nuevosTotales = {};

        for (let i = 0; i < meses; i++) {
            const d = new Date(
                fechaInicio.getFullYear(),
                fechaInicio.getMonth() + i,
                1
            );

            const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
            const label = d.toLocaleString('es', { month: 'short', year: 'numeric' });

            nuevosMeses.push({ key, label });
            nuevosTotales[key] = 0;
        }

        const map = {};

        data.forEach(item => {
            if (!map[item.polizaId]) {
                map[item.polizaId] = {
                    polizaId: item.polizaId,
                    numeroPoliza: item.numeroPoliza,
                    asegurado: item.aseguradoNombre,
                    aseguradora: item.aseguradora,
                    formaPago: item.formaPago,
                    estatusPoliza: item.estatusPoliza,
                    fechaUltimoPago: this.formatearFecha(item.fechaUltimoPago),
                    rowClass: item.esPolizaInactiva ? 'fila-inactiva' : '',
                    celdas: nuevosMeses.map(m => ({
                        key: `${item.polizaId}-${m.key}`,
                        mesKey: m.key,
                        monto: null,
                        tieneValor: false,
                        esPagoReal: false,
                        estaPagado: false,
                        tieneMontoPendiente: false,
                        tieneMezclaVigencia: false,
                        tieneArrastre: false,

                        montoPagadoMXN: 0,
                        montoPendienteMXN: 0,
                        montoProyectadoMXN: 0,

                        clase: ''
                        }))
                };
            }

            if (!item.fechaEsperadaPago) return;

            const keyMes = item.fechaEsperadaPago.substring(0, 7);
            const fila = map[item.polizaId];
            const celda = fila.celdas.find(c => c.mesKey === keyMes);

            if (!celda) {
                console.warn('Mes fuera de rango:', keyMes, 'para poliza', item.polizaId);
            }

            if (celda) {
                celda.monto = item.monto;
                celda.tieneValor = true;
                celda.esPagoReal = item.esPagoReal;
                celda.estaPagado = item.estaPagado;

                celda.tieneMontoPendiente = !!item.tieneMontoPendiente;
                celda.tieneMezclaVigencia = !!item.tieneMezclaVigencia;
                celda.tieneArrastre = !!item.tieneArrastre;

                celda.montoPagadoMXN = item.montoPagadoMXN || 0;
                celda.montoPendienteMXN = item.montoPendienteMXN || 0;
                celda.montoProyectadoMXN = item.montoProyectadoMXN || 0;
                celda.montoDisplay = this.formatearMonedaSinDecimales(item.monto);

                // PRIORIDAD DE COLOR
                if (celda.tieneMezclaVigencia) {
                    // PÚRPURA (cruce nueva vigencia)
                    celda.clase = 'monto-cruce-nueva-vigencia';
                }
                else if (celda.tieneArrastre) {
                    // MAGENTA (arrastre vigencia anterior)
                    celda.clase = 'monto-arrastre';
                }
                else if (celda.esPagoReal && celda.estaPagado && celda.tieneMontoPendiente) {
                    // AZUL (pagado + pendiente)
                    celda.clase = 'monto-pagado-pendiente';
                }
                else if (celda.esPagoReal && celda.estaPagado) {
                    // VERDE (pagado)
                    celda.clase = 'monto-pagado';
                }
                else if (celda.esPagoReal && !celda.estaPagado) {
                    // ROJO (pendiente existente)
                    celda.clase = 'monto-pendiente';
                }
                else if (item.esNuevaVigencia) {
                    // NARANJA (proyección nueva vigencia)
                    celda.clase = 'monto-proyectado-nueva-vigencia';
                }
                else {
                    // NEGRO/DEFAULT (proyección normal)
                    celda.clase = 'monto-proyectado';
                }

                nuevosTotales[keyMes] += item.monto;
            }
        });

        this.mesesMatriz = [...nuevosMeses];
        this.totalesPorMes = { ...nuevosTotales };
        this.matrizData = [...Object.values(map)];
        // this.aplicarOrdenamiento();
        this.paginaActualMatriz = 1;
        this.actualizarPaginacionMatriz();
    }

    //Métodos de filtros
    handlePolizaChange(event) {
        this.filtroPolizaId = event.detail.recordId;
        this.recalcularVista();
    }
    
    handleAseguradoChange(event) {
        this.filtroAseguradoId = event.detail.recordId || null;
        this.recalcularVista();
    }
    
    handleAseguradoraChange(event) {
        this.filtroAseguradora = event.detail.value;
        this.recalcularVista();
    }

    handleFiltroEstatusPolizaChange(event) {
        this.filtroEstatusPoliza = event.detail.value;
        this.recalcularVista();
    }

    handleEstatusReciboChange(event) {
        this.filtroEstatusRecibo = event.detail.value;

        this.construirVistaMensual();
        this.paginaActualMensual = 1;
        this.actualizarPaginacionMensual();
    }

    handleMesesChange(event) {
        this.cantidadMeses = event.detail.value;
        this.handleBuscar();
    }

    handleMesChange(event) { 
        this.mesSeleccionado = event.detail.value;
        this.handleBuscar();
    }

    handleAnioChange(event) { 
        this.anioSeleccionado = event.detail.value;
        this.handleBuscar();
    }

    aplicarFiltros(data) {
        return data.filter(item => {

            if (this.filtroPolizaId &&
                item.polizaId !== this.filtroPolizaId) {
                return false;
            }

            if (this.filtroAseguradoId &&
                item.aseguradoId !== this.filtroAseguradoId) {
                return false;
            }

            if (this.filtroAseguradora &&
                item.aseguradora !== this.filtroAseguradora) {
                return false;
            }

            if (this.filtroEstatusPoliza &&
                item.estatusPoliza !== this.filtroEstatusPoliza) {
                return false;
            }

            return true;
        });
    }

    //Métodos de paginación
    actualizarPaginacionMensual() {
        const size = parseInt(this.tamanoPaginaMensual, 10);
        const inicio = (this.paginaActualMensual - 1) * size;
        const fin = inicio + size;
        this.dataMensualPaginada = this.dataMensual.slice(inicio, fin);
    }

    actualizarPaginacionMatriz() {
        const size = parseInt(this.tamanoPaginaMatriz, 10);
        const inicio = (this.paginaActualMatriz - 1) * size;
        const fin = inicio + size;
        this.dataMatrizPaginada = this.matrizData.slice(inicio, fin);
    }

    //Métodos de Modal
    handleRowAction(event) {
        const poliza = event.detail.row.numeroPoliza;
        this.template.querySelector('c-cobranza-poliza-pagos-modal').cargar(poliza);
    }

    abrirDetallePoliza(event) {
        const numeroPoliza = event.currentTarget.dataset.poliza;
        this.template
            .querySelector('c-cobranza-poliza-pagos-modal')
            .cargar(numeroPoliza);
    }

    //Getters
    get esMensual() {
        return this.modoVista === 'mensual';
    }

    get esMatriz() {
        return this.modoVista === 'matriz';
    }

    get labelMesSeleccionado(){
        if(this.modoVista === 'matriz'){
            return 'Mes Inicial';
        }else{
            return 'Mes';
        }
    }

    get labelAnioSeleccionado(){
        if(this.modoVista === 'matriz'){
            return 'Año Inicial';
        }else{
            return 'Año';
        }
    }

    get btnMensual() {
        return this.esMensual ? 'brand' : 'neutral';
    }

    get btnMatriz() {
        return this.esMatriz ? 'brand' : 'neutral';
    }

    get totalPaginas() {
        if (this.esMensual) {
             return Math.ceil(this.dataMensual.length / parseInt(this.tamanoPaginaMensual, 10)) || 1;
        } else {
            return Math.ceil(this.matrizData.length / parseInt(this.tamanoPaginaMatriz, 10)) || 1;
        }
    }

    get mostrandoDesde() {
        if (this.esMensual) {
            if (!this.dataMensual || !this.dataMensual.length) return 0;
            const size = parseInt(this.tamanoPaginaMensual, 10);
            return (this.paginaActualMensual - 1) * size + 1;
        } else {
            if (!this.matrizData || !this.matrizData.length) return 0;
            const size = parseInt(this.tamanoPaginaMatriz, 10);
            return (this.paginaActualMatriz - 1) * size + 1;
        }
    }

    get mostrandoHasta() {
        if (this.esMensual) {
            if (!this.dataMensual || !this.dataMensual.length) return 0;
            const size = parseInt(this.tamanoPaginaMensual, 10);
            const hasta = this.paginaActualMensual * size;
            return hasta > this.dataMensual.length ? this.dataMensual.length : hasta;
        } else {
            if (!this.matrizData || !this.matrizData.length) return 0;
            const size = parseInt(this.tamanoPaginaMatriz, 10);
            const hasta = this.paginaActualMatriz * size;
            return hasta > this.matrizData.length ? this.matrizData.length : hasta;
        }
    }

    get deshabilitarAnterior() {
        return this.esMensual
            ? this.paginaActualMensual <= 1
            : this.paginaActualMatriz <= 1;
    }

    get deshabilitarSiguiente() {
        return this.esMensual
            ? this.paginaActualMensual >= this.totalPaginas
            : this.paginaActualMatriz >= this.totalPaginas;
    }

    get tamanoPaginaActual() {
        return this.esMensual ? this.tamanoPaginaMensual : this.tamanoPaginaMatriz;
    }

    get totalRegistrosVista() {
        return this.esMensual
            ? (this.dataMensual ? this.dataMensual.length : 0)
            : (this.matrizData ? this.matrizData.length : 0);
    }

    get paginaActualVista() {
        return this.esMensual
            ? this.paginaActualMensual
            : this.paginaActualMatriz;
    }

    get dataActivaKPI() {
        if (this.esMensual) {
            return (this.dataMensual || []).map(r => ({
            montoPagadoMXN: r.montoPagadoMXN || 0,
            montoPendienteMXN: r.montoPendienteMXN || 0,
            montoProyectadoMXN: r.montoProyectadoMXN || 0
            }));
        }

        if (!this.matrizData) return [];

        return this.matrizData.flatMap(row =>
            (row.celdas || [])
            .filter(c => c.tieneValor)
            .map(c => ({
                montoPagadoMXN: c.montoPagadoMXN || 0,
                montoPendienteMXN: c.montoPendienteMXN || 0,
                montoProyectadoMXN: c.montoProyectadoMXN || 0
            }))
        );
    }

    get kpiResumen() {
        const data = this.dataActivaKPI;

        let pagado = 0, pendiente = 0, proyectado = 0;
        let cPag = 0, cPen = 0, cProy = 0;

        for (const r of data) {
            const mp = r.montoPagadoMXN || 0;
            const mpen = r.montoPendienteMXN || 0;
            const mproy = r.montoProyectadoMXN || 0;

            pagado += mp;
            pendiente += mpen;
            proyectado += mproy;

            if (mp > 0) cPag++;
            if (mpen > 0) cPen++;
            if (mproy > 0) cProy++;
        }

        const cTotal = cPag + cPen + cProy;
        const totalMonetario = pagado + pendiente + proyectado;
        const porcentaje = totalMonetario ? (pagado / totalMonetario) * 100 : 0;

        return { pagado, pendiente, proyectado, cPag, cPen, cProy, cTotal, totalMonetario, porcentaje };
    }

    get kpiCards() {
        const k = this.kpiResumen;

        return [
            {
            key: 'pagado',
            variant: 'pagado',
            label: 'Total Pagado',
            value: this.formatearMoneda(k.pagado),
            count: `${k.cPag} registros`
            },
            {
            key: 'pendiente',
            variant: 'pendiente',
            label: 'Total Pendiente',
            value: this.formatearMoneda(k.pendiente),
            count: `${k.cPen} registros`
            },
            {
            key: 'proyectado',
            variant: 'proyectado',
            label: 'Total Proyectado',
            value: this.formatearMoneda(k.proyectado),
            count: `${k.cProy} registros`
            },
            {
            key: 'cobranza',
            variant: 'cobranza',
            label: '% Cobranza',
            value: this.formatearPorcentaje(k.porcentaje),
            count: `${k.cPag} de ${k.cTotal} registros`
            }
        ];
    }

    //Métodos Helper utilitarios
    formatearMoneda(valor) {
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(valor || 0);
    }

    formatearPorcentaje(valor) {
        return new Intl.NumberFormat('es-MX', {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
        }).format(valor || 0) + '%';
    }

    formatearFecha(fecha) {
        if (!fecha) return '';

        const d = new Date(fecha);
        const dia = String(d.getDate()).padStart(2, '0');
        const mes = String(d.getMonth() + 1).padStart(2, '0');
        const anio = d.getFullYear();

        return `${dia}/${mes}/${anio}`;
    }

    formatearMonedaSinDecimales(valor) {
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(valor || 0);
    }

    generarRangoMensual(mes, anio) {
        const desde = new Date(anio, mes, 1);
        const hasta = new Date(anio, mes + 1, 0);
        return { fechaDesde: this.formatDate(desde), fechaHasta: this.formatDate(hasta) };
    }

    formatDate(fecha) {
        return fecha.toISOString().split('T')[0];
    }

    normalizarFechaISO(fecha) {
        if (!fecha) return null;

        if (typeof fecha === 'string' && fecha.length === 10) {
            return `${fecha}T12:00:00.000Z`;
        }

        return fecha;
    }

    parseDateLocal(ymdOrIso) {
        if (!ymdOrIso) return null;
        const ymd = ymdOrIso.substring(0, 10);
        const [y, m, d] = ymd.split('-').map(n => parseInt(n, 10));
        return new Date(y, m - 1, d);
    }

}