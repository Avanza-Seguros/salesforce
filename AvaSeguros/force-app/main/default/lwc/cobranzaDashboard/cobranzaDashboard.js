import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUltimosPagosPoliza from '@salesforce/apex/CobranzaController.getUltimosPagosPolizaEficiente';
import getEstadisticasPorMesYEstatusConFechas from '@salesforce/apex/CobranzaController.getEstadisticasPorMesYEstatusConFechas';
import getPoliza from '@salesforce/apex/CobranzaController.getPoliza';
import getPagosPol from '@salesforce/apex/CobranzaController.getPagosPol';
import ChartJS from '@salesforce/resourceUrl/chartJs';
import { loadScript } from 'lightning/platformResourceLoader';

const ESTATUS_OPCIONES = [
    { label: 'Todos', value: '' },
    { label: 'Pendiente', value: 'Pendiente' },
    { label: 'Pagado', value: 'Pagado' },
    { label: 'Cancelado', value: 'Cancelado' },
    { label: 'Vencido', value: 'Vencido' }
];

const ESTATUS_POLIZA_OPCIONES = [
    { label: 'Todos', value: '' },
    { label: 'En Vigor', value: 'Vigor' },
    { label: 'Renovada', value: 'Renovada' },
    { label: 'Cancelada', value: 'Cancelada' },
    { label: 'Vencida', value: 'Vencida' },
    { label: 'No tomada	', value: 'No tomada' }
];

const ASEGURADORA_OPCIONES = [
    {label: 'Todas', value: '' },
    {label:'Afirme',value:'Afirme'},
    {label:'AXA',value:'AXA'},
    {label:'Bx+',value:'Bx+'},
    {label:'GNP',value:'GNP'},
    {label:'Mapfre',value:'Mapfre'},
    {label:'PlanSeguro',value:'PlanSeguro'},
    {label:'SMNYL',value:'SMNYL'},
    {label:'Insignia',value:'Insignia'},
    {label:'QUALITAS',value:'QUALITAS'},
    {label:'CHUBB',value:'CHUBB'},
    {label:'HDI',value:'HDI'},
    {label:'ATLAS',value:'ATLAS'},
    {label:'AIGAIG',value:'AIGAIG'},
    {label:'INBURSA',value:'INBURSA'},
    {label:'SISNOVA',value:'SISNOVA'},
    {label:'Dentegra',value:'Dentegra'},
    {label:'VRIM',value:'VRIM'},
    {label:'Zurich',value:'Zurich'},
    {label:'Sura',value:'Sura'},
    {label:'GMX',value:'GMX'},
    {label:'Safelink',value:'Safelink'},
    {label:'Berkley',value:'Berkley'},
    {label:'Allianz',value:'Allianz'},
    {label:'Bupa',value:'Bupa'},
    {label:'Sofimex',value:'Sofimex'},
    {label:'Prudential',value:'Prudential'},
    {label:'Metlife',value:'Metlife'},
    {label:'Aserta',value:'Aserta'},
    {label:'Terrawin',value:'Terrawin'},
    {label:'Banorte',value:'Banorte'}
];

const TIPO_GRAFICA_OPCIONES = [
    { label: 'Barras Apiladas - Pagado vs Pendiente', value: 'bar-apiladas' }
];

export default class CobranzaDashboard extends LightningElement {
    @track pagos = [];
    @track filteredPagos = [];
    @track selectedPagos = [];
    @track isLoading = false;
    @track searchTerm = '';
    @track selectedPago = null;
    
    @track filtros = {
        estatus: '',
        estatusPoliza: '',
        aseguradora: '',
        fechaDesde: '',
        fechaHasta: '',
        montoMinimo: '',
        montoMaximo: ''
    };

    @track filtrosGrafica = {
        estatus: '',
        rangoFechas: 'mesActual',
        tipoGrafica: 'bar-apiladas'
    };

    @track estadisticas = {
        totalPendientes: 0,
        totalPagados: 0,
        totalCancelados: 0,
        totalVencidos: 0,
        montoTotalPendiente: 0,
        montoTotalPagado: 0
    };

    @track currentPage = 1;
    @track pageSize = 10;
    @track totalPages = 1;
    @track paginatedData = [];
    @track detallePago = '';

    // ✅ CORREGIDO: Columnas con tooltips funcionando
    columns = [
        {
            label: 'Póliza',
            fieldName: 'Poliza_sc__c',
            type: 'text',
            sortable: true
        },
        {
            label: 'Aseguradora',
            fieldName: 'Aseguradora__c',
            type: 'text',
            sortable: true
        },
        {
            label: 'Cliente',
            fieldName: 'Cliente__c',
            type: 'text',
            sortable: true,
            cellAttributes: { 
                class: { fieldName: 'clienteIcon' },
                title: { fieldName: 'clienteTooltip' }
            },
            wrapText: true
        },
        {
            label: 'Folio',
            fieldName: 'Folio__c',
            type: 'text',
            sortable: true
        },
        {
            label: 'Forma de pago',
            fieldName: 'Forma_pago__c',
            type: 'text',
            sortable: true
        },
        {
            label: 'Pago de recibo',
            fieldName: 'Fecha_de_Aplicaci_n_del_pago__c',
            type: 'date',
            sortable: true,
            typeAttributes: {
                day: 'numeric',
                month: 'numeric',
                year: 'numeric'
            }
        },
        {
            label: 'Proximo pago',
            fieldName: 'Proximo_Pago__c',
            type: 'date',
            sortable: true,
            typeAttributes: {
                day: 'numeric',
                month: 'numeric',
                year: 'numeric'
            }
        },
        {
            label: 'Estatus recibo',
            fieldName: 'Estatus_pago__c',
            type: 'text',
            cellAttributes: { 
                class: { fieldName: 'statusClass' },
                iconName: { fieldName: 'statusIcon' },
                iconPosition: 'left'
            }
        },
        {
            label: 'Estatus poliza',
            fieldName: 'Estatus_Poliza_Actual__c',
            type: 'text',
            sortable: true
        },
        {
            label: 'Canal Cobro',
            fieldName: 'Canal_de_Cobro__c',
            type: 'text',
            sortable: true
        },
        {
            label: 'Monto',
            fieldName: 'Monto__c',
            type: 'currency',
            typeAttributes: { 
                currencyCode: 'MXN',
                step: '0.01'
            },
            sortable: true
        },
        {
            label: 'Monto del pago',
            fieldName: 'Pago_en_MXN__c',
            type: 'currency',
            typeAttributes: { 
                currencyCode: 'MXN',
                step: '0.01'
            },
            sortable: true
        },
        {
            label: 'Fecha vencimiento',
            fieldName: 'Fecha_de_de_Vencimiento__c',
            type: 'date',
            sortable: true,
            typeAttributes: {
                day: 'numeric',
                month: 'numeric',
                year: 'numeric'
            }
        },
        {
            label: 'Ver Detalles',
            type: 'action',
            typeAttributes: {
                rowActions: this.getRowActions, // ✅ CORREGIDO: Referencia correcta
                menuAlignment: 'right'
            }
        }
    ];

    // Variables para gráficas
    @track resumenPagos = [];
    @track chart;
    @track chartData = null;
    @track datosOriginales = [];
    chartLoaded = false;
    chartInitialized = false;

    @track modalData = {};
    @track modalType = '';
    @track showDetallesModal = false;

    // ✅ CORREGIDO: Método para obtener acciones de fila
    getRowActions(row, doneCallback) {
        const actions = [{
            label: 'Ver Detalles',
            name: 'detalles',
            iconName: 'utility:preview'
        }];
        doneCallback(actions);
    }

    // ✅ CORREGIDO: Un solo método handleRowAction
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        
        console.log('🔄 Acción en fila:', action.name, row.Id);
        
        this.abrirModalDetalles(row);
    }

    // ✅ CORREGIDO: Método para abrir modal de detalles
    async abrirModalDetalles(pago) {
        console.log('🎯 Abriendo modal para pago:', JSON.stringify(pago));
        const pagos = await getPagosPol({ pagoPol: pago.Id });
        const poliza = await getPoliza({ idPol: pago.Poliza__c }); 
        console.log('📄 Datos de póliza obtenidos:', JSON.stringify(poliza));
        console.log('📄 Datos de pagos obtenidos:', JSON.stringify(pagos));
        this.detallePago = `Detalles del Pago - ${pago.Poliza_sc__c}`;
        this.modalData = {
            titulo: 'Detalles del Pago', 
            pagos: pagos,
            pago: pago,
            poliza: poliza,
            modo: 'lectura'
        };
        this.modalType = 'detalles';
        this.showDetallesModal = true;
    }

    // ✅ CORREGIDO: Manejar cierre del modal
    handleModalClose(event) {
        console.log('🗑️ Cerrando modal');
        this.showDetallesModal = false;
        this.modalData = {};
        this.modalType = '';
    }

    renderedCallback() {
        if (!this.chartLoaded) {
            this.inicializarChart();
        }
    }

    async inicializarChart() {
        try {
            await loadScript(this, ChartJS);
            this.chartLoaded = true;
            console.log('✅ Chart.js cargado');
        } catch (error) {
            console.error('❌ Error cargando Chart.js:', error);
        }
    }

    async connectedCallback() {
        this.obtenerRangoMensual();
        console.log('📅 Filtros iniciales de fecha:', this.filtros.fechaDesde, 'a', this.filtros.fechaHasta);
        await this.inicializarDatos();
    }


    obtenerRangoMensual() {
        const hoy = new Date();
        const primerDiaMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);

        let fechaDesde;
        let fechaHasta;

        // Verificar si HOY es el primer día del mes (solo comparando día)
        if (hoy.getDate() === 1) {
            // Si hoy es día 1 del mes
            fechaDesde = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 0); // Último día mes anterior
            fechaHasta = hoy; // Hasta hoy (que es día 1)
        } else {
            // Si hoy NO es día 1
            fechaDesde = primerDiaMes;
            fechaHasta = hoy;
        }
        
        this.filtros.fechaDesde = this.formatDateForInput(fechaDesde);
        this.filtros.fechaHasta = this.formatDateForInput(fechaHasta);
        console.log('📅 Rango de fechas establecido:', this.filtros.fechaDesde, 'a', this.filtros.fechaHasta);
    }

    async inicializarDatos() {
        this.isLoading = true;
        try {
            await this.cargarDatosPagos();
            await this.cargarDatosGraficas();
            await this.calcularEstadisticas();
        } catch (error) {
            console.error('❌ Error inicializando datos:', error);
        } finally {
            this.isLoading = false;
        }
    }

    async cargarDatosPagos() {
        try {
            const result = await getUltimosPagosPoliza({
                fechaInicio: this.filtros.fechaDesde,
                fechaFin: this.filtros.fechaHasta
            });
            console.log('📄 Resultado de getUltimosPagosPoliza:', JSON.stringify(result));
            this.resumenPagos = this.procesarPagos(result) || [];
            console.log('📊 Resumen pagos:', JSON.stringify(this.resumenPagos));
            this.filteredPagos = [...this.resumenPagos];
            console.log('🔍 Pagos filtrados:', JSON.stringify(this.filteredPagos));
            this.actualizarPaginacion();
            
        } catch (error) {
            console.error('❌ Error cargando pagos:', error);
            this.resumenPagos = [];
            this.filteredPagos = [];
        }
    }

    // ✅ NUEVO: Método para aplicar rango de fechas específico
    async aplicarRangoFechas(rango) {
        const hoy = new Date();
        let fechaInicio, fechaFin;

        switch(rango) {
            case 'mesActual':
                fechaInicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
                fechaFin = hoy;
                break;
            case 'mesAnterior':
                fechaInicio = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1);
                fechaFin = new Date(hoy.getFullYear(), hoy.getMonth(), 0);
                break;
            case 'ultimos3Meses':
                fechaInicio = new Date(hoy.getFullYear(), hoy.getMonth() - 3, 1);
                fechaFin = hoy;
                break;
            case 'ultimos6Meses':
                fechaInicio = new Date(hoy.getFullYear(), hoy.getMonth() - 6, 1);
                fechaFin = hoy;
                break;
            case 'anioActual':
                fechaInicio = new Date(hoy.getFullYear(), 0, 1);
                fechaFin = hoy;
                break;
            default:
                return;
        }

        this.filtros.fechaDesde = this.formatDateForInput(fechaInicio);
        this.filtros.fechaHasta = this.formatDateForInput(fechaFin);
        
        console.log(`📅 Aplicando rango: ${rango}`, this.filtros.fechaDesde, 'a', this.filtros.fechaHasta);
        
        await this.recargarGraficas();
        await this.filtrarPagos();
    }

    // ✅ NUEVO: Opciones de rango rápido
    get opcionesRango() {
        return [
            { label: 'Mes Actual', value: 'mesActual' },
            { label: 'Mes Anterior', value: 'mesAnterior' },
            { label: 'Últimos 3 Meses', value: 'ultimos3Meses' },
            { label: 'Últimos 6 Meses', value: 'ultimos6Meses' },
            { label: 'Año Actual', value: 'anioActual' }
        ];
    }

    // ✅ NUEVO: Manejar cambio de rango rápido
    async handleRangoRapidoChange(event) {
        const rango = event.target.value;
        if (rango) {
            await this.aplicarRangoFechas(rango);
        }
    }

    // ✅ NUEVO: Aplicar filtros actuales a gráficas
    async aplicarFiltrosAGraficas() {
        console.log('🎯 Aplicando filtros actuales a gráficas');
        await this.recargarGraficas();
    }

    // ✅ NUEVO: Método para recargar gráficas cuando cambien los filtros
    async recargarGraficas() {
        console.log('🔄 Recargando gráficas con nuevos filtros');
        this.isLoading = true;
        try {
            await this.cargarDatosGraficas();
        } catch (error) {
            console.error('❌ Error recargando gráficas:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ✅ NUEVO: Método para cargar datos de gráficas con filtros
    async cargarDatosGraficas() {
        try {
            console.log('📅 Cargando gráficas con fechas:', this.filtros.fechaDesde, 'a', this.filtros.fechaHasta);
            
            // Convertir fechas string a Date para Apex
            const fechaInicio = this.filtros.fechaDesde ? new Date(this.filtros.fechaDesde) : null;
            const fechaFin = this.filtros.fechaHasta ? new Date(this.filtros.fechaHasta) : null;
            
            const result = await getEstadisticasPorMesYEstatusConFechas({
                fechaInicio: fechaInicio,
                fechaFin: fechaFin
            });
            
            console.log('📈 Datos para gráficas (con filtros):', result);
            
            if (result && result.length > 0) {
                this.datosOriginales = result;
                await this.aplicarFiltrosGrafica();
            } else {
                this.chartData = this.getDatosVaciosConMensaje('No hay datos en el rango seleccionado');
                this.renderizarChart();
            }
        } catch (error) {
            console.error('❌ Error cargando datos gráficas con filtros:', error);
            // ✅ FALLBACK: Intentar sin filtros si falla
        }
    }

    renderizarChart() {
        if (!this.chartLoaded || !this.chartData) {
            console.log('❌ Chart.js no cargado o sin datos');
            return;
        }

        const canvas = this.template.querySelector('canvas.mi-grafica');
        if (!canvas) {
            console.error('❌ Canvas no encontrado');
            return;
        }

        console.log('🎨 Renderizando gráfica - Tipo:', this.filtrosGrafica.tipoGrafica);

        // ✅ LIMPIAR COMPLETAMENTE el canvas y destruir chart anterior
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        if (this.chart) {
            try {
                this.chart.destroy();
                this.chart = null;
            } catch (e) {
                console.log('⚠️ Error destruyendo gráfica anterior:', e);
            }
        }

        // ✅ CONFIGURACIÓN ESPECÍFICA PARA COMBINADA
        let config;
        
        // ✅ ACTUALIZADO: Incluir barras apiladas
        if(this.filtrosGrafica.tipoGrafica) {
            config = this.getConfiguracionBarrasApiladas();
        }

        try {
            console.log('🔄 Creando gráfica con config:', config);
            this.chart = new window.Chart(ctx, config);
            this.chartInitialized = true;
            console.log('✅ Gráfica creada exitosamente');
        } catch (error) {
            console.error('❌ Error crítico al crear gráfica:', error);
            console.error('🔍 Stack trace:', error.stack);
        }
    }

    // ✅ NUEVO: Configuración para barras apiladas
    getConfiguracionBarrasApiladas() {
        return {
            type: 'bar',
            data: this.chartData,
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: this.obtenerTituloGrafica(),
                        font: { size: 16, weight: 'bold' }
                    },
                    legend: {
                        display: true,
                        position: 'top',
                    },
                    tooltip: {
                        mode: 'index',
                        callbacks: {
                            label: (context) => {
                                const datasetLabel = context.dataset.label || '';
                                const value = context.parsed.y;
                                const total = context.dataset.data.reduce((acc, data, index) => {
                                    return acc + this.chartData.datasets[index].data[context.dataIndex];
                                }, 0);
                                
                                const percentage = total > 0 ? Math.round((value / total) * 100) : 0;
                                return ` ${datasetLabel}: $${value.toLocaleString('es-MX')} MXN (${percentage}%)`;
                            },
                            footer: (tooltipItems) => {
                                if (tooltipItems.length > 0) {
                                    const dataIndex = tooltipItems[0].dataIndex;
                                    const total = tooltipItems.reduce((sum, tooltipItem) => {
                                        return sum + tooltipItem.parsed.y;
                                    }, 0);
                                    
                                    return `Total: $${total.toLocaleString('es-MX')} MXN`;
                                }
                                return '';
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        stacked: true, // ✅ IMPORTANTE: Eje X apilado
                        title: {
                            display: true,
                            text: 'Meses'
                        },
                        grid: {
                            display: false
                        }
                    },
                    y: {
                        stacked: true, // ✅ IMPORTANTE: Eje Y apilado
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Monto Total (MXN)',
                            font: { weight: 'bold' }
                        },
                        ticks: {
                            callback: (value) => {
                                if (value >= 1000000) {
                                    return `$${(value / 1000000).toFixed(1)}M`;
                                } else if (value >= 1000) {
                                    return `$${(value / 1000).toFixed(0)}K`;
                                }
                                return `$${value}`;
                            }
                        }
                    }
                },
                interaction: {
                    intersect: false,
                    mode: 'index'
                }
            }
        };
    }

    // ✅ ACTUALIZADO: Título que incluye información de fechas
    obtenerTituloGrafica() {
        const estatus = this.filtrosGrafica.estatus ? ` - ${this.filtrosGrafica.estatus}` : '';
        let rangoFechas = '';
        
        // ✅ AGREGAR INFORMACIÓN DE RANGO DE FECHAS
        if (this.filtros.fechaDesde && this.filtros.fechaHasta) {
            const desde = new Date(this.filtros.fechaDesde).toLocaleDateString('es-MX');
            const hasta = new Date(this.filtros.fechaHasta).toLocaleDateString('es-MX');
            rangoFechas = ` (${desde} a ${hasta})`;
        }
        
        if(this.filtrosGrafica.tipoGrafica) {
            return `Pagado vs Pendiente por Mes${rangoFechas}`;
        }
    }

    // ✅ MEJORADO: Aplicar filtros con mejor manejo de errores
    async aplicarFiltrosGrafica() {
        if (!this.datosOriginales || this.datosOriginales.length === 0) {
            console.log('⚠️ No hay datos originales para filtrar');
            this.chartData = this.getDatosVacios();
            this.renderizarChart();
            return;
        }

        let datosFiltrados = [...this.datosOriginales];

        if (datosFiltrados.length === 0) {
            console.log('⚠️ No hay datos después del filtrado');
            this.chartData = this.getDatosVaciosConMensaje(`No hay datos para: ${this.filtrosGrafica.estatus}`);
            this.renderizarChart();
            return;
        }

        try {
            console.log(`🎨 Preparando gráfica: ${this.filtrosGrafica.tipoGrafica}`);
            
            if(this.filtrosGrafica.tipoGrafica) {
                this.chartData = this.prepararDatosBarrasApiladas(datosFiltrados);
            }

            console.log('✅ Datos preparados exitosamente');
            this.renderizarChart();
            
        } catch (error) {
            console.error('❌ Error al preparar datos para gráfica:', error);
            this.chartData = this.getDatosVaciosConMensaje('Error procesando datos');
            this.renderizarChart();
        }
    }

    // ✅ NUEVO: Preparar datos para gráfica de barras apiladas
    prepararDatosBarrasApiladas(data) {
        console.log('🔄 Preparando datos para barras apiladas');
        
        if (!data || data.length === 0) {
            return this.getDatosVacios();
        }

        // Agrupar por mes y año, separando pagado vs pendiente
        const grupos = this.agruparPorMesYEstatus(data);
        const labels = [];
        const datosPagados = [];
        const datosPendientes = [];
        const datosVencidos = [];
        const datosCancelados = [];

        grupos.forEach(grupo => {
            const label = `${this.obtenerNombreMesCorto(grupo.mes)} ${grupo.anio}`;
            labels.push(label);
            
            // Buscar los datos para cada estatus en este mes
            const pagado = grupo.estatus.find(e => e.estatus === 'Pagado');
            const pendiente = grupo.estatus.find(e => e.estatus === 'Pendiente');
            const vencido = grupo.estatus.find(e => e.estatus === 'Vencido');
            const cancelado = grupo.estatus.find(e => e.estatus === 'Cancelado');
            
            datosPagados.push(pagado ? pagado.montoTotal : 0);
            datosPendientes.push(pendiente ? pendiente.montoTotal : 0);
            datosVencidos.push(vencido ? vencido.montoTotal : 0);
            datosCancelados.push(cancelado ? cancelado.montoTotal : 0);
        });

        console.log('📊 Barras apiladas - Labels:', JSON.stringify(labels));
        console.log('📊 Barras apiladas - Pagados:', JSON.stringify(datosPagados));
        console.log('📊 Barras apiladas - Pendientes:', JSON.stringify(datosPendientes));
        console.log('📊 Barras apiladas - Vencidos:', JSON.stringify(datosVencidos));
        console.log('📊 Barras apiladas - Cancelados:', JSON.stringify(datosCancelados));
        return {
            labels: labels,
            datasets: [
                {
                    label: 'Pagado',
                    data: datosPagados,
                    backgroundColor: '#4CAF50', // Verde
                    borderColor: '#2E7D32',
                    borderWidth: 1,
                    stack: 'Stack 0' // ✅ Mismo stack para apilar
                },
                {
                    label: 'Pendiente',
                    data: datosPendientes,
                    backgroundColor: '#FF9800', // Naranja
                    borderColor: '#EF6C00',
                    borderWidth: 1,
                    stack: 'Stack 0' // ✅ Mismo stack para apilar
                },
                {
                    label: 'Vencido',
                    data: datosVencidos,
                    backgroundColor: '#F44336', // Rojo
                    borderColor: '#C62828',
                    borderWidth: 1,
                    stack: 'Stack 0' // ✅ Mismo stack para apilar
                },
                {
                    label: 'Cancelado',
                    data: datosCancelados,
                    backgroundColor: '#9E9E9E', // Gris
                    borderColor: '#616161',
                    borderWidth: 1,
                    stack: 'Stack 0' // ✅ Mismo stack para apilar
                }
            ]
        };
    }

    // ✅ NUEVO: Agrupar datos por mes y estatus
    agruparPorMesYEstatus(data) {
        console.log('🔄 Agrupando datos por mes y estatus');
        console.log('🔍 Datos de entrada:', JSON.stringify(data));
        const grupos = {};
        
        data.forEach(item => {
            const anio = item.anio || new Date().getFullYear();
            const mes = item.mes || 1;
            const estatus = item.estatus || 'Sin Estatus';
            const monto = Number(item.montoTotal) || 0;
            
            const key = `${anio}-${mes}`;
            
            if (!grupos[key]) {
                grupos[key] = {
                    anio: anio,
                    mes: mes,
                    estatus: []
                };
            }
            
            // Buscar si ya existe este estatus en el grupo
            const estatusExistente = grupos[key].estatus.find(e => e.estatus === estatus);
            
            if (estatusExistente) {
                estatusExistente.montoTotal += monto;
                estatusExistente.totalPagos += Number(item.totalPagos) || 0;
            } else {
                grupos[key].estatus.push({
                    estatus: estatus,
                    montoTotal: monto,
                    totalPagos: Number(item.totalPagos) || 0
                });
            }
        });

        // Ordenar por año y mes
        const resultado = Object.values(grupos).sort((a, b) => {
            if (a.anio !== b.anio) return a.anio - b.anio;
            return a.mes - b.mes;
        });

        console.log('📊 Grupos por estatus:', JSON.stringify(resultado));
        return resultado;
    }

    // ✅ MEJORADO: Procesar pagos con tooltips y estilos
    procesarPagos(pagos) {
        if (!pagos) return [];
        
        return pagos.map(pago => {
            const hoy = new Date();
            const vencimiento = pago.Proximo_Pago__c ? new Date(pago.Proximo_Pago__c) : null;

            let estatus = pago.Estatus_pago__c || 'Pendiente';
            let statusClass = '';
            let statusIcon = 'utility:question';
            let rowClass = '';
            console.log(`🔍 Procesando pago con estatus inicial: ${estatus}`);
            // ✅ CORREGIDO: Determinar clases e iconos correctamente
            switch(estatus) {
                case 'Pagado':
                    statusClass = 'estado-badge-pagado';
                    statusIcon = 'utility:check';
                    rowClass = 'fila-pagada';
                    break;
                case 'Pendiente':
                    statusClass = 'estado-badge-pendiente';
                    statusIcon = 'utility:warning';
                    rowClass = 'fila-pendiente';
                    break;
                case 'Cancelado':
                    statusClass = 'estado-badge-cancelado';
                    statusIcon = 'utility:clear';
                    rowClass = 'fila-cancelada';
                    break;
                case 'Vencido':
                    statusClass = 'estado-badge-vencido';
                    statusIcon = 'utility:error';
                    rowClass = 'fila-vencida';
                    break;
            }

            // ✅ CORREGIDO: Generar tooltips correctamente
            const clienteTooltip = this.generarTooltipCliente(pago);
            const clienteIcon = this.obtenerIconoCliente(pago);

            console.log(`🔧 Procesando pago ${pago.Id}:`, {
                estatus,
                statusClass,
                statusIcon,
                rowClass,
                clienteTooltip,
                clienteIcon
            });

            return {
                ...pago,
                Estatus_pago__c: estatus,
                statusClass: statusClass, // ✅ Para celda de estatus
                statusIcon: statusIcon,   // ✅ Para celda de estatus
                rowClass: rowClass,       // ✅ Para fila completa
                isSelected: false,
                
                // ✅ TOOLTIPS CORRECTOS
                clienteTooltip: clienteTooltip,
                clienteIcon: clienteIcon
            };
        });
    }

    // ✅ CORREGIDO: Generar tooltip del cliente
    generarTooltipCliente(pago) {        
        return `👤 ${pago.Cliente__c || 'Cliente no especificado'}`;
    }

    // ✅ CORREGIDO: Generar tooltip de póliza
    generarTooltipPoliza(pago) {
       return `📋 ${pago.Poliza_sc__c || 'Sin póliza'}`;
    }

    obtenerEstadoCliente(pago) {
        const estatus = pago.Estatus_pago__c;
        
        switch(estatus) {
            case 'Pagado': return '✅ Cliente al corriente';
            case 'Pendiente': return '⏳ Pago pendiente';
            case 'Vencido': return '❌ Cliente moroso';
            case 'Cancelado': return '🚫 Póliza cancelada';
            default: return 'ℹ️ Estado no definido';
        }
    }

    obtenerIconoCliente(pago) {
        const estatus = pago.Estatus_pago__c;
        
        if (estatus === 'Pagado') return 'utility:like';
        if (estatus === 'Vencido') return 'utility:warning';
        if (estatus === 'Pendiente') return 'utility:priority';
        return 'standard:account';
    }

    // ✅ CORREGIDO: Manejar filtros de tabla
    async handleFilterChange(event) {
        this.isLoading = true;
        const field = event.target.name;
        const value = event.target.value;
        this.filtros[field] = value;
        await this.filtrarPagos();
        this.isLoading = false;
    }

    async handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
        await this.filtrarPagos();
    }

    // ✅ CORREGIDO: Filtrar pagos
    async filtrarPagos() {
        const result = await getUltimosPagosPoliza({
                fechaInicio: this.filtros.fechaDesde,
                fechaFin: this.filtros.fechaHasta
            });
        console.log('Resultado de getUltimosPagosPoliza para filtrado:', JSON.stringify(result));
        this.resumenPagos = this.procesarPagos(result) || [];

        let resultados = [...this.resumenPagos];
        console.log('🔍 Resumen pagos:', JSON.stringify(this.resumenPagos));
        // Filtro por búsqueda
        if (this.searchTerm) {
            resultados = resultados.filter(pago => 
                (pago.Poliza_sc__c && pago.Poliza_sc__c.toLowerCase().includes(this.searchTerm)) ||
                (pago.Cliente__c && pago.Cliente__c.toLowerCase().includes(this.searchTerm)) ||
                (pago.Folio__c && pago.Folio__c.toLowerCase().includes(this.searchTerm)) ||
                (pago.Aseguradora__c && pago.Aseguradora__c.toLowerCase().includes(this.searchTerm))
            );
        }

        // Filtro por estatus
        if (this.filtros.estatusPoliza) {
            resultados = resultados.filter(pago => pago.Estatus_Poliza_Actual__c === this.filtros.estatusPoliza);
        }

        // Filtro por estatus
        if (this.filtros.estatus) {
            resultados = resultados.filter(pago => pago.Estatus_pago__c === this.filtros.estatus);
        }

        // Filtro por canal de cobro
        if (this.filtros.aseguradora) {
            resultados = resultados.filter(pago => pago.Aseguradora__c === this.filtros.aseguradora);
        }

    /*
        if (this.filtros.fechaDesde) {
            const fechaDesde = new Date(this.filtros.fechaDesde);
            resultados = resultados.filter(pago => pago.Proximo_Pago__c >= fechaDesde);
        }

        if (this.filtros.fechaHasta) {
            const fechaHasta = new Date(this.filtros.fechaHasta);
            resultados = resultados.filter(pago => pago.Proximo_Pago__c < fechaHasta);
        }
    */
        this.filteredPagos = resultados;
        this.actualizarPaginacion();
        await this.calcularEstadisticas();
    }

    // ✅ NUEVO: Paginación
    actualizarPaginacion() {
        this.totalPages = Math.ceil(this.filteredPagos.length / this.pageSize);
        this.currentPage = 1;
        this.actualizarDatosPagina();
    }

    actualizarDatosPagina() {
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = startIndex + this.pageSize;
        this.paginatedData = this.filteredPagos.slice(startIndex, endIndex);
    }

    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.actualizarDatosPagina();
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.actualizarDatosPagina();
        }
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.target.value, 10);
        this.actualizarPaginacion();
    }

    // ✅ CORREGIDO: Calcular estadísticas
    async calcularEstadisticas() {
        const stats = {
            totalPendientes: 0,
            totalPagados: 0,
            totalCancelados: 0,
            totalVencidos: 0,
            montoTotalPendiente: 0,
            montoTotalPagado: 0,
            montoTotalCancelado: 0,
            montoTotalVencido: 0
        };

        this.filteredPagos.forEach(pago => {
            const monto = pago.Pago_en_MXN__c || 0;
            switch(pago.Estatus_pago__c) {
                case 'Pendiente':
                    stats.totalPendientes++;
                    stats.montoTotalPendiente += monto;
                    break;
                case 'Pagado':
                    stats.totalPagados++;
                    stats.montoTotalPagado += monto;
                    break;
                case 'Cancelado':
                    stats.totalCancelados++;
                    stats.montoTotalCancelado += monto;
                    break;
                case 'Vencido':
                    stats.totalVencidos++;
                    stats.montoTotalVencido += monto;
                    break;
            }
        });
        this.estadisticas = stats;
    }

    // ✅ CORREGIDO: Limpiar filtros
    async limpiarFiltros() {
        this.searchTerm = '';
        this.filtros = {
            estatus: '',
            estatusPoliza: '',
            aseguradora: '',
            fechaDesde: this.filtros.fechaDesde, // Mantener fechas
            fechaHasta: this.filtros.fechaHasta,
            montoMinimo: '',
            montoMaximo: ''
        };
        await this.filtrarPagos();
    }

    async limpiarFiltrosGrafica() {
        this.filtrosGrafica = {
            estatus: '',
            tipoGrafica: 'bar-apiladas'
        };
        await this.aplicarFiltrosGrafica();
    }

    // ✅ CORREGIDO: Getters
    get montoPendiente() {
        return this.estadisticas.montoTotalPendiente.toFixed(2);
    }

    get montoPagado() {
        return this.estadisticas.montoTotalPagado.toFixed(2);
    }

    get hayDatosParaGrafica() {
        return this.chartData && this.chartData.labels && this.chartData.labels.length > 0;
    }

    get estatusOpciones() {
        return ESTATUS_OPCIONES;
    }

    get estatusPolizaOpciones() {
        return ESTATUS_POLIZA_OPCIONES;
    }

    get aseguradoraOpciones() {
        return ASEGURADORA_OPCIONES;
    }

    get tipoGraficaOpciones() {
        return TIPO_GRAFICA_OPCIONES;
    }

    get paginationInfo() {
        const start = ((this.currentPage - 1) * this.pageSize) + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.filteredPagos.length);
        return `Mostrando ${start}-${end} de ${this.filteredPagos.length} registros`;
    }

    verDetallesPago(row) {
        this.selectedPago = row;
        this.showDetallesModal = true;
    }

    getDatosVacios() {
        return {
            labels: ['No hay datos'],
            datasets: [{
                label: 'Sin datos',
                data: [0],
                backgroundColor: 'rgba(200, 200, 200, 0.6)'
            }]
        };
    }

    getDatosVaciosConMensaje(mensaje) {
        return {
            labels: [mensaje],
            datasets: [{
                label: 'Sin datos',
                data: [1],
                backgroundColor: 'rgba(200, 200, 200, 0.6)'
            }]
        };
    }

    oscurecerColor(color, factor) {
        const hex = color.replace('#', '');
        const num = parseInt(hex, 16);
        const amt = Math.round(2.55 * factor * 100);
        const R = Math.max(0, (num >> 16) - amt);
        const G = Math.max(0, (num >> 8 & 0x00FF) - amt);
        const B = Math.max(0, (num & 0x0000FF) - amt);
        return '#' + (
            0x1000000 + (R < 255 ? R : 255) * 0x10000 + 
            (G < 255 ? G : 255) * 0x100 + (B < 255 ? B : 255)
        ).toString(16).slice(1);
    }

    obtenerNombreMesCorto(numeroMes) {
        const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 
                      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        const mesIndex = Math.max(0, Math.min(11, (numeroMes - 1) || 0));
        return meses[mesIndex];
    }

    formatDateForInput(date) {
        return date.toISOString().split('T')[0];
    }

    get paginaAnterior(){
        return this.currentPage === 1;
    }

    get paginaSiguiente(){
        return this.currentPage === this.totalPages;
    }

    get graficaApilada() {
        return this.filtrosGrafica.tipoGrafica === 'bar-apiladas';
    }

    get fechaDesdeFormateada() {
        const date = new Date(this.filtros.fechaDesde);
        return date.toLocaleDateString('es-MX');
    }

    get fechaHastaFormateada() {
        const date = new Date(this.filtros.fechaHasta);
        return date.toLocaleDateString('es-MX');
    }
}