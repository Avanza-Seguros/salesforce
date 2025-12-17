import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import buscarHistorico from '@salesforce/apex/HistoricoPolizasController.buscarHistorico';
import obtenerHistoricoPorRelacion from '@salesforce/apex/HistoricoPolizasController.obtenerHistoricoPorRelacion';

export default class RtHistoricoPolizas extends LightningElement {
    @track resultados = [];
    @track isLoading = false;
    @track searchTerm = '';
    @track detalleCompleto = null;
    @track mostrarDetalles = false;
    @track mostrarTabla = true;
    @track errorMessage = '';

    // Variables de paginación para tabla principal
    @track currentPage = 1;
    @track pageSize = 10;
    @track totalPages = 1;
    @track paginatedResults = [];

    // Variables de paginación para pagos
    @track currentPagePagos = 1;
    @track pageSizePagos = 5;
    @track totalPagesPagos = 1;

    // Variables de paginación para históricos
    @track currentPageHistoricos = 1;
    @track pageSizeHistoricos = 5;
    @track totalPagesHistoricos = 1;

    connectedCallback() {
        console.log('Componente rtHistoricoPolizas cargado');
        this.cargarPolizasIniciales();
    }

    async cargarPolizasIniciales() {
        console.log('Cargando pólizas iniciales');
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.resultados = await buscarHistorico({ searchTerm: '' });
            console.log('Pólizas cargadas:', JSON.stringify(this.resultados));
            this.currentPage = 1;
            this.calcularPaginas();
            if (this.resultados.length === 0) {
                this.mostrarToast('Información', 'No se encontraron pólizas', 'info');
            }
        } catch (error) {
            console.error('Error cargando pólizas:', error);
            this.errorMessage = this.obtenerMensajeError(error);
            this.mostrarToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Manejar cambio en el input de búsqueda
    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    // Ejecutar búsqueda al hacer clic en el botón
    async handleBuscar() {
        if (!this.searchTerm || this.searchTerm.length < 2) {
            this.mostrarToast('Advertencia', 'Ingresa al menos 2 caracteres para buscar', 'warning');
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.resultados = await buscarHistorico({ searchTerm: this.searchTerm });
            this.currentPage = 1;
            this.calcularPaginas();
            if (this.resultados.length === 0) {
                this.mostrarToast('Información', 'No se encontraron pólizas con ese criterio', 'info');
            }
        } catch (error) {
            console.error('Error buscando pólizas:', error);
            this.errorMessage = this.obtenerMensajeError(error);
            this.mostrarToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Limpiar búsqueda y mostrar todas las pólizas
    handleLimpiar() {
        this.searchTerm = '';
        this.errorMessage = '';
        this.cargarPolizasIniciales();
    }

    // 📄 Seleccionar relación/póliza
    async seleccionarRelacion(event) {
        console.log('Seleccionando relación/póliza');
        const relacionId = event.currentTarget.dataset.id;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.detalleCompleto = await obtenerHistoricoPorRelacion({ relacionId });
            this.mostrarDetalles = true;
            this.mostrarTabla = false;
            // Resetear paginación de detalles
            this.currentPagePagos = 1;
            this.currentPageHistoricos = 1;
            this.calcularPaginasPagos();
            this.calcularPaginasHistoricos();
        } catch (error) {
            console.error('Error al obtener detalles:', error);
            this.errorMessage = this.obtenerMensajeError(error);
            this.mostrarToast('Error', this.errorMessage, 'error');
            // Regresar a la vista de tabla si hay error
            this.mostrarDetalles = false;
            this.mostrarTabla = true;
        } finally {
            this.isLoading = false;
        }
    }

    volverALista() {
        this.mostrarDetalles = false;
        this.mostrarTabla = true;
        this.detalleCompleto = null;
        this.errorMessage = '';
        this.currentPage = 1;
        this.calcularPaginas();
    }

    // Paginación - Tabla Principal
    calcularPaginas() {
        console.log('Cálculo de páginas - Tabla Principal');
        this.totalPages = Math.ceil(this.resultados.length / this.pageSize);
        this.actualizarPaginaActual();
    }

    actualizarPaginaActual() {
        console.log('Actualización de página actual - Tabla Principal');
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.paginatedResults = this.resultadosProcesados.slice(start, end);
    }

    anteriorPagina() {
        console.log('Navegando a la página anterior - Tabla Principal');
        if (this.currentPage > 1) {
            this.currentPage--;
            this.actualizarPaginaActual();
        }
    }

    siguientePagina() {
        console.log('Navegando a la página siguiente - Tabla Principal');
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.actualizarPaginaActual();
        }
    }

    irAPagina(event) {
        console.log('Navegando a página específica - Tabla Principal');
        const pagina = parseInt(event.target.value);
        if (pagina >= 1 && pagina <= this.totalPages) {
            this.currentPage = pagina;
            this.actualizarPaginaActual();
        }
    }

    // Paginación - Pagos
    calcularPaginasPagos() {
        console.log('Cálculo de páginas - Pagos');
        this.totalPagesPagos = Math.ceil(this.pagos.length / this.pageSizePagos);
    }

    get pagosPaginados() {
        console.log('Obteniendo pagos paginados');
        if (!this.tienePagos) return [];
        const start = (this.currentPagePagos - 1) * this.pageSizePagos;
        const end = start + this.pageSizePagos;
        return this.pagosProcesadosParaTabla.slice(start, end);
    }

    anteriorPaginaPagos() {
        if (this.currentPagePagos > 1) {
            this.currentPagePagos--;
        }
    }

    siguientePaginaPagos() {
        if (this.currentPagePagos < this.totalPagesPagos) {
            this.currentPagePagos++;
        }
    }

    irAPaginaPagos(event) {
        const pagina = parseInt(event.target.value);
        if (pagina >= 1 && pagina <= this.totalPagesPagos) {
            this.currentPagePagos = pagina;
        }
    }

    // Paginación - Históricos
    calcularPaginasHistoricos() {
        this.totalPagesHistoricos = Math.ceil(this.historicos.length / this.pageSizeHistoricos);
    }

    get historicosPaginados() {
        if (!this.tieneHistoricos) return [];
        const start = (this.currentPageHistoricos - 1) * this.pageSizeHistoricos;
        const end = start + this.pageSizeHistoricos;
        return this.historicosProcesadosParaTabla.slice(start, end);
    }

    anteriorPaginaHistoricos() {
        if (this.currentPageHistoricos > 1) {
            this.currentPageHistoricos--;
        }
    }

    siguientePaginaHistoricos() {
        if (this.currentPageHistoricos < this.totalPagesHistoricos) {
            this.currentPageHistoricos++;
        }
    }

    irAPaginaHistoricos(event) {
        const pagina = parseInt(event.target.value);
        if (pagina >= 1 && pagina <= this.totalPagesHistoricos) {
            this.currentPageHistoricos = pagina;
        }
    }

    // Resto de métodos permanecen igual...
    async recargarDetalles() {
        if (!this.detalleCompleto || !this.detalleCompleto.relacionPrincipal) return;
        
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.detalleCompleto = await obtenerHistoricoPorRelacion({
                relacionId: this.detalleCompleto.relacionPrincipal.relacionId
            });
            this.calcularPaginasPagos();
            this.calcularPaginasHistoricos();
            this.mostrarToast('Éxito', 'Detalles actualizados', 'success');
        } catch (error) {
            console.error('Error recargando detalles:', error);
            this.errorMessage = this.obtenerMensajeError(error);
            this.mostrarToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Función para obtener mensajes de error más amigables
    obtenerMensajeError(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        } else if (typeof error === 'string') {
            return error;
        } else {
            return 'Error desconocido al comunicarse con el servidor';
        }
    }

    mostrarToast(titulo, mensaje, variante) {
        this.dispatchEvent(new ShowToastEvent({ 
            title: titulo, 
            message: mensaje, 
            variant: variante,
            mode: 'dismissable'
        }));
    }

    // Función auxiliar para manejar valores nulos
    getValorSeguro(valor) {
        if (valor === null || valor === undefined) return 'N/A';
        return valor;
    }

    getFechaSegura(fecha) {
        if (!fecha) return 'N/A';
        return fecha;
    }

    // Función para formatear montos monetarios
    formatearMoneda(valor) {
        if (!valor || isNaN(valor)) return 'N/A';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN'
        }).format(valor);
    }

    // Getters computados
    get tieneResultados() {
        return this.resultados && this.resultados.length > 0;
    }

    get tieneError() {
        return this.errorMessage && this.errorMessage.length > 0;
    }

    get totalResultados() {
        return this.resultados.length;
    }

    // Getters para paginación - Información de páginas
    get paginaInfo() {
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalResultados);
        return `Mostrando ${start}-${end} de ${this.totalResultados} registros`;
    }

    get paginaInfoPagos() {
        if (!this.tienePagos) return '';
        const start = (this.currentPagePagos - 1) * this.pageSizePagos + 1;
        const end = Math.min(this.currentPagePagos * this.pageSizePagos, this.pagos.length);
        return `Mostrando ${start}-${end} de ${this.pagos.length} registros`;
    }

    get paginaInfoHistoricos() {
        if (!this.tieneHistoricos) return '';
        const start = (this.currentPageHistoricos - 1) * this.pageSizeHistoricos + 1;
        const end = Math.min(this.currentPageHistoricos * this.pageSizeHistoricos, this.historicos.length);
        return `Mostrando ${start}-${end} de ${this.historicos.length} registros`;
    }

    // Getters para los datos del detalle (sin cambios)
    get relacionSeleccionada() {
        return this.detalleCompleto ? this.detalleCompleto.relacionPrincipal : null;
    }

    get asegurados() {
        return this.detalleCompleto ? this.detalleCompleto.asegurados : [];
    }

    get historicos() {
        return this.detalleCompleto ? this.detalleCompleto.historicos : [];
    }

    get pagos() {
        return this.detalleCompleto ? this.detalleCompleto.pagos : [];
    }

    get relaciones() {
        return this.detalleCompleto ? this.detalleCompleto.relaciones : [];
    }

    get poliza() {
        return this.detalleCompleto ? this.detalleCompleto.poliza : null;
    }

    get tieneAsegurados() {
        return this.asegurados && this.asegurados.length > 0;
    }

    get tieneHistoricos() {
        return this.historicos && this.historicos.length > 0;
    }

    get tienePagos() {
        return this.pagos && this.pagos.length > 0;
    }

    get tieneRelaciones() {
        return this.relaciones && this.relaciones.length > 0;
    }

    // Getters computados para procesar datos (sin cambios, solo se actualizaron los nombres)
    get resultadosProcesados() {
        console.log('Procesando resultados');
        console.log('Resultados originales:', this.resultados);
        if (!this.resultados) return [];
        
        return this.resultados.map(relacion => {
            return {
                ...relacion,
                polizaNameSeguro: this.getValorSeguro(relacion.polizaName),
                relacionNameSeguro: this.getValorSeguro(relacion.relacionName),
                estatusSeguro: this.getValorSeguro(relacion.estatus),
                aseguradoNameSeguro: relacion.asegurado && relacion.asegurado.name ? 
                    relacion.asegurado.name : 'No asignado',
                sumaAseguradaSeguro: this.getValorSeguro(relacion.sumaAsegurada),
                primaTotalSeguro: this.getValorSeguro(relacion.primaTotal),
                fechaEmisionSegura: this.getFechaSegura(relacion.fechaEmision),
                estatusClass: relacion.estatus === 'Activa' || relacion.estatus === 'Vigente' ? 
                    'slds-theme_success' : 'slds-theme_warning'
            };
        });
    }

    get polizaProcesada() {
        if (!this.poliza) {
            return {
                name: 'N/A',
                estatus: 'N/A',
                planProducto: 'N/A',
                moneda: 'N/A',
                sumaAsegurada: '0',
                primaTotal: '0',
                fechaEmision: Date.today(),
                fechaVencimiento: Date.today()
            };
        }
        
        return {
            name: this.getValorSeguro(this.poliza.name),
            estatus: this.getValorSeguro(this.poliza.estatus),
            planProducto: this.getValorSeguro(this.poliza.planProducto),
            moneda: this.getValorSeguro(this.poliza.moneda),
            sumaAsegurada: this.getValorSeguro(this.poliza.sumaAsegurada) || '0',
            primaTotal: this.getValorSeguro(this.poliza.primaTotal) || '0',
            fechaEmision: this.getFechaSegura(this.poliza.fechaEmision),
            fechaVencimiento: this.getFechaSegura(this.poliza.fechaVencimiento) || Date.today()
        };
    }

    get aseguradosProcesados() {
        if (!this.asegurados) return [];
        
        return this.asegurados.map(asegurado => ({
            ...asegurado,
            name: this.getValorSeguro(asegurado.name),
            email: this.getValorSeguro(asegurado.email),
            fechaNacimiento: this.getFechaSegura(asegurado.fechaNacimiento)
        }));
    }

    get pagosProcesadosParaTabla() {
        console.log('Procesando pagos para tabla');
        console.log('Pagos originales:', this.pagos);
        if (!this.pagos) return [];
        
        return this.pagos.map(pago => ({
            ...pago,
            name: this.getValorSeguro(pago.name),
            importe: this.getValorSeguro(pago.importe),
            moneda: this.getValorSeguro(pago.moneda),
            pagoMXN: this.getValorSeguro(pago.pagoMXN),
            tipoPago: this.getValorSeguro(pago.tipoPago),
            fecha: this.getFechaSegura(pago.fecha),
            estatusPago: this.getValorSeguro(pago.estatusPago),
            estatusPagoClass: pago.estatusPago === 'Completado' || pago.estatusPago === 'Aprobado' ? 
                'slds-theme_success' : pago.estatusPago === 'Pendiente' ? 'slds-theme_warning' : 'slds-theme_error'
        }));
    }

    get historicosProcesadosParaTabla() {
        console.log('Historicos', this.historicos);
        if (!this.historicos) return [];
        return this.historicos.map(historico => ({
            ...historico,
            name: this.getValorSeguro(historico.name),
            anualidad: this.getValorSeguro(historico.anualidad),
            primaBasica: this.getValorSeguro(historico.primaBasica),
            primaAdicional: this.getValorSeguro(historico.primaAdicional),
            pagosIngresados: this.getValorSeguro(historico.pagosIngresados),
            desde: this.getFechaSegura(historico.desde),
            hasta: this.getFechaSegura(historico.hasta),
            primaTotal: (parseFloat(historico.primaBasica) + parseFloat(historico.primaAdicional)).toFixed(2) || this.getValorSeguro(relacion.primaTotal),
            periodo: `${this.getFechaSegura(historico.desde)} - ${this.getFechaSegura(historico.hasta)}`
        }));
    }

    // Métodos para cambiar el tamaño de página
    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.target.value);
        this.currentPage = 1;
        this.calcularPaginas();
    }

    handlePageSizePagosChange(event) {
        this.pageSizePagos = parseInt(event.target.value);
        this.currentPagePagos = 1;
        this.calcularPaginasPagos();
    }

    handlePageSizeHistoricosChange(event) {
        this.pageSizeHistoricos = parseInt(event.target.value);
        this.currentPageHistoricos = 1;
        this.calcularPaginasHistoricos();
    }

    get currentPageTotalPages() {
        return this.currentPage === this.totalPages;
    }

    get currentPageIsFirst() {
        return this.currentPage === 1;
    }

    get currentPagePagosTotalPagesPagos() {
        return this.currentPagePagos === this.totalPagesPagos;
    }

    get currentPagePagosIsFirst() {
        return this.currentPagePagos === 1;
    }

    get currentPageHistoricosTotalPagesHistoricos() {
        return this.currentPageHistoricos === this.totalPagesHistoricos;
    }

    get currentPageHistoricosIsFirst() {
        return this.currentPageHistoricos === 1;
    }

    get totalPagesPagosIsGreaterThanOne() {
        return this.totalPagesPagos > 1;
    }

    get totalPagesHistoricosIsGreaterThanOne() {
        return this.totalPagesHistoricos > 1;
    }

    // Análisis financiero de la póliza
    get analisisFinanciero() {
        console.log('Iniciando análisis financiero');
        // Valores por defecto
        const defaultAnalysis = {
            estado: 'Sin información suficiente',
            color: 'slds-theme_warning',
            totalPrimas: 0,
            totalPagos: 0,
            diferencia: 0,
            tieneAdeudo: false,
            tieneExceso: false,
            alCorriente: false,
            mensaje: 'No hay suficiente información para realizar el análisis'
        };
        console.log('Poliza:', this.poliza);
        console.log('Historicos:', this.tieneHistoricos);
        if (!this.poliza || !this.tieneHistoricos) {
            return defaultAnalysis;
        }

        try {
            // Calcular total de primas (suma de todas las primas básicas y adicionales)
            const totalPrimas = this.historicos.reduce((sum, historico) => {
                const primaBasica = parseFloat(historico.primaBasica) || 0;
                const primaAdicional = parseFloat(historico.primaAdicional) || 0;
                return sum + primaBasica + primaAdicional;
            }, 0);

            // Calcular total de pagos
            const totalPagos = this.tienePagos ? 
                this.pagos.reduce((sum, pago) => {
                    const importe = parseFloat(pago.importe) || 0;
                    return sum + importe;
                }, 0) : 0;
            console.log('Total Primas:', totalPrimas);
            console.log('Total Pagos:', totalPagos);
            const diferencia = totalPrimas - totalPagos;
            
            // Determinar estado
            let estado, color, mensaje;
            console.log('Diferencia:', diferencia);

            if (diferencia === 0) {
                estado = 'Al corriente';
                color = 'slds-theme_success';
                mensaje = 'La póliza está completamente al corriente. No hay adeudos.';
            } else if (diferencia > 0) {
                estado = 'Adeudo pendiente';
                color = 'slds-theme_error';
                mensaje = `La póliza tiene un adeudo pendiente de ${this.formatearMoneda(diferencia)}`;
            } else {
                estado = 'Pagos en exceso';
                color = 'slds-theme_info';
                mensaje = `La póliza tiene pagos en exceso por ${this.formatearMoneda(Math.abs(diferencia))}`;
            }

            return {
                estado,
                color,
                totalPrimas,
                totalPagos,
                diferencia: Math.abs(diferencia),
                tieneAdeudo: diferencia > 0,
                tieneExceso: diferencia < 0,
                alCorriente: diferencia === 0,
                mensaje
            };
        } catch (error) {
            console.error('Error en análisis financiero:', error);
            return defaultAnalysis;
        }
    }

    // Porcentaje de cumplimiento
    get porcentajeCumplimiento() {
        if (!this.analisisFinanciero.totalPrimas) return 0;
        const porcentaje = (this.analisisFinanciero.totalPagos / this.analisisFinanciero.totalPrimas) * 100;
        return Math.min(porcentaje, 100); // Máximo 100%
    }

    // Estado de la póliza basado en fechas
    get estadoVigencia() {
        console.log('Calculando estado de vigencia');
        console.log('Poliza:', this.poliza);
        if (!this.poliza || !this.poliza.fechaVencimiento) {
            return {
                estado: 'Fecha desconocida',
                color: 'slds-theme_warning',
                mensaje: 'No se puede determinar la vigencia'
            };
        }

        const hoy = new Date();
        const vencimiento = new Date(this.poliza.fechaVencimiento);
        const diffTime = vencimiento.getTime() - hoy.getTime();
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

        let estado, color, mensaje;
        console.log('Días para vencimiento:', diffDays);
        if (diffDays < 0) {
            estado = 'Vencida';
            color = 'slds-theme_error';
            mensaje = `La póliza venció hace ${Math.abs(diffDays)} días`;
        } else if (diffDays <= 30) {
            estado = 'Por vencer';
            color = 'slds-theme_warning';
            mensaje = `La póliza vence en ${diffDays} días`;
        } else {
            estado = 'Vigente';
            color = 'slds-theme_success';
            mensaje = `La póliza está vigente por ${diffDays} días más`;
        }

        return {
            estado,
            color,
            diffDays: Math.abs(diffDays),
            mensaje
        };
    }

    // Resumen ejecutivo
    get resumenEjecutivo() {
        console.log('Generando resumen ejecutivo');
        return {
            estadoGeneral: this.analisisFinanciero.tieneAdeudo && this.estadoVigencia.estado === 'Vencida' ? 'Crítico' :
                        this.analisisFinanciero.tieneAdeudo ? 'Atención requerida' :
                        this.analisisFinanciero.alCorriente ? 'Saludable' : 'En revisión',
            colorGeneral: this.estadoVigencia.estado === 'Vencida' ? 'slds-theme_error' :
                        this.analisisFinanciero.tieneAdeudo ? 'slds-theme_warning' :
                        this.analisisFinanciero.alCorriente ? 'slds-theme_success' : 'slds-theme_info',
            recomendacion: this.generarRecomendacion(this.analisisFinanciero, this.estadoVigencia)
        };
    }

    // Generar recomendación automática
    generarRecomendacion(analisis, vigencia) {
        console.log('Generando recomendación basada en análisis y vigencia');
        console.log('Análisis Financiero:', analisis);
        console.log('Estado de Vigencia:', vigencia);
        if (analisis.tieneAdeudo && vigencia.estado === 'Vencida') {
            return 'Póliza vencida con adeudo. Se requiere atención inmediata y renovación.';
        } else if (analisis.tieneAdeudo && vigencia.estado === 'Por vencer') {
            return 'Adeudo pendiente y póliza por vencer. Regularizar pagos antes del vencimiento.';
        } else if (analisis.tieneAdeudo) {
            return 'Existe un adeudo pendiente. Se recomienda regularizar el pago.';
        } else if (vigencia.estado === 'Por vencer') {
            return 'Póliza por vencer. Considerar renovación oportuna.';
        } else if (analisis.alCorriente && vigencia.estado === 'Vigente') {
            return 'Póliza en excelente estado. Mantener pagos al corriente.';
        } else {
            return 'Revisar estado de la póliza.';
        }
    }

    get estadoGeneralSaludable() {
        console.log('Estado General:', this.resumenEjecutivo.estadoGeneral);
        return this.resumenEjecutivo.estadoGeneral === 'Saludable';
    }

    get estadoGeneralAtencionRequerida() {
        console.log('Estado General:', this.resumenEjecutivo.estadoGeneral);
        return this.resumenEjecutivo.estadoGeneral === 'Atención requerida';
    }

    get estadoGeneralCritico() {
        console.log('Estado General:', this.resumenEjecutivo.estadoGeneral);
        return this.resumenEjecutivo.estadoGeneral === 'Crítico';
    }

    get vigenciaVigente() {
        console.log('Estado Vigencia:', this.estadoVigencia.estado);
        return this.estadoVigencia.estado === 'Vigente';
    }

    get vigenciaPorVencer() {
        console.log('Estado Vigencia:', this.estadoVigencia.estado);
        return this.estadoVigencia.estado === 'Por vencer';
    }

    get vigenciaVencida() {
        console.log('Estado Vigencia:', this.estadoVigencia.estado);
        return this.estadoVigencia.estado === 'Vencida';
    }

    // También necesitamos asegurarnos de que porcentajeCumplimiento tenga un valor por defecto
    get porcentajeCumplimiento() {
        console.log('Cálculo de porcentajeCumplimiento');
        console.log('Analisis Financiero:', this.analisisFinanciero);
        if (!this.analisisFinanciero.totalPrimas) return 0;
        const porcentaje = (this.analisisFinanciero.totalPagos / this.analisisFinanciero.totalPrimas) * 100;
        return Math.min(Math.max(porcentaje, 0), 100); // Entre 0% y 100%
    }

    // Agregar estos getters para los estilos de la barra de progreso
    get claseBarraProgreso() {
        console.log('Cálculo de claseBarraProgreso');
        console.log('Porcentaje Cumplimiento:', this.porcentajeCumplimiento);
        if (this.porcentajeCumplimiento >= 100) {
            return 'slds-progress-bar__value slds-theme_success';
        } else if (this.porcentajeCumplimiento >= 80) {
            return 'slds-progress-bar__value slds-theme_warning';
        } else {
            return 'slds-progress-bar__value slds-theme_error';
        }
    }

    get estiloBarraProgreso() {
        console.log('Porcentaje Cumplimiento para estilo:', this.porcentajeCumplimiento);
        const porcentaje = this.porcentajeCumplimiento;
        // Asegurarse de que el porcentaje esté entre 0 y 100
        const porcentajeAjustado = Math.min(Math.max(porcentaje, 0), 100);
        return `width: ${porcentajeAjustado}%`;
    }

    // Método para formatear números grandes (opcional)
    formatearNumeroGrande(valor) {
        if (!valor || isNaN(valor)) return '0';
        if (valor >= 1000000) {
            return (valor / 1000000).toFixed(1) + 'M';
        } else if (valor >= 1000) {
            return (valor / 1000).toFixed(1) + 'K';
        }
        return valor.toString();
    }

    // Getters para manejar las expresiones condicionales
    get signoDiferencia() {
        return this.analisisFinanciero.tieneAdeudo ? '-' : '+';
    }

    get claseColorDiferencia() {
        console.log('Cálculo de claseColorDiferencia');
        return this.analisisFinanciero.tieneAdeudo ? 'slds-text-color_error' : 'slds-text-color_success';
    }

    get textoEstadoPago() {
        console.log('Porcentaje Cumplimiento para textoEstadoPago:', this.porcentajeCumplimiento);
        const porcentaje = this.porcentajeCumplimiento;
        if (porcentaje >= 100) return '✅ Pagos completos';
        if (porcentaje >= 80) return '⚠️ Casi completo';
        return '❌ Pagos pendientes';
    }

    get iconoEstadoGeneral() {
        console.log('Resumen Ejecutivo Estado General:', this.resumenEjecutivo);
        const estado = this.resumenEjecutivo.estadoGeneral;
        if (estado === 'Saludable') return 'custom:custom1';
        if (estado === 'Atención requerida') return 'action:close';
        if (estado === 'En revisión') return 'action:approval';
        return 'utility:error';
    }

    get iconoEstadoVigencia() {
        console.log('Estado Vigencia:', this.estadoVigencia);
        const estado = this.estadoVigencia.estado;
        if (estado === 'Vigente') return 'action:goal';
        if (estado === 'Por vencer') return 'utility:warning';
        return 'utility:ban';
    }

    get iconoEstadoFinanciero() {
        console.log('Análisis Financiero:', this.analisisFinanciero);
        if (this.analisisFinanciero.alCorriente) return 'action:approval';
        if (this.analisisFinanciero.tieneAdeudo) return 'utility:moneybag';
        return 'utility:money';
    }
    

    // Getters para controlar la visualización de alertas
    get mostrarAlertaPorVencer() {
        console.log('Estado Vigencia:', this.estadoVigencia);
        return this.estadoVigencia.estado === 'Por vencer';
    }

    get mostrarAlertaVencida() {
        console.log('Estado Vigencia:', this.estadoVigencia);
        return this.estadoVigencia.estado === 'Vencida';
    }

    // Getters para valores formateados
    get porcentajeCumplimientoFormateado() {
        return this.porcentajeCumplimiento.toFixed(1);
    }

    get diferenciaFormateada() {
        return this.formatearMoneda(this.analisisFinanciero.diferencia);
    }

    get totalPrimasFormateado() {
        return this.formatearMoneda(this.analisisFinanciero.totalPrimas);
    }

    get totalPagosFormateado() {
        return this.formatearMoneda(this.analisisFinanciero.totalPagos);
    }

    get diferenciaCompleta() {
        return `${this.signoDiferencia}${this.formatearMoneda(this.analisisFinanciero.diferencia)}`;
    }

    // Getters para los textos de asistencia
    get textoAsistenciaBarra() {
        return `Progreso: ${this.porcentajeCumplimiento.toFixed(1)}%`;
    }

    // Asegurarnos de que porcentajeCumplimiento tenga valores válidos
    get porcentajeCumplimiento() {
        if (!this.analisisFinanciero || !this.analisisFinanciero.totalPrimas) return 0;
        const porcentaje = (this.analisisFinanciero.totalPagos / this.analisisFinanciero.totalPrimas) * 100;
        return Math.min(Math.max(porcentaje, 0), 100); // Entre 0% y 100%
    }

    // Getters para clases CSS dinámicas
    get claseTarjetaDiferencia() {
        console.log('Cálculo de claseTarjetaDiferencia');
        console.log('Análisis Financiero:', this.analisisFinanciero);
        if (this.analisisFinanciero.tieneAdeudo) return 'slds-theme_error';
        if (this.analisisFinanciero.alCorriente) return 'slds-theme_success';
        return 'slds-theme_info';
    }

    get claseMetricaDiferencia() {
        console.log('Cálculo de claseMetricaDiferencia');
        console.log('Análisis Financiero:', this.analisisFinanciero);
        if (this.analisisFinanciero.tieneAdeudo) return 'slds-theme_error';
        if (this.analisisFinanciero.alCorriente) return 'slds-theme_success';
        return 'slds-theme_info';
    }

    get claseTextoProgreso() {
        const porcentaje = this.porcentajeCumplimiento;
        if (porcentaje >= 100) return 'slds-text-color_success';
        if (porcentaje >= 80) return 'slds-text-color_warning';
        return 'slds-text-color_error';
    }

    // Getter para el texto del saldo
    get textoSaldo() {
        console.log('Análisis Financiero:', this.analisisFinanciero);
        if (this.analisisFinanciero.tieneAdeudo) return 'Adeudo pendiente';
        if (this.analisisFinanciero.alCorriente) return 'Al corriente';
        return 'Pagos en exceso';
    }

    get estadoVigenciaSeguro() {
        console.log('Estado Vigencia:', this.estadoVigencia);
        return this.estadoVigencia || {
            estado: 'Sin información',
            color: 'slds-theme_warning',
            mensaje: 'No se puede determinar la vigencia',
            diffDays: 0
        };
    }

    get analisisFinancieroSeguro() {
        console.log('Análisis Financiero:', this.analisisFinanciero);
        return this.analisisFinanciero || {
            estado: 'Sin información',
            color: 'slds-theme_warning',
            totalPrimas: 0,
            totalPagos: 0,
            diferencia: 0,
            tieneAdeudo: false,
            tieneExceso: false,
            alCorriente: false,
            mensaje: 'No hay suficiente información para el análisis'
        };
    }

    get resumenEjecutivoSeguro() {
        console.log('Resumen Ejecutivo:', this.resumenEjecutivo);
        return this.resumenEjecutivo || {
            estadoGeneral: 'En revisión',
            colorGeneral: 'slds-theme_info',
            recomendacion: 'Información en proceso de carga'
        };
    }

    // Agregar estos getters para las clases CSS personalizadas
    get claseEstadoGeneral() {
        console.log('Resumen Ejecutivo Estado General:', this.resumenEjecutivo);
        if (this.resumenEjecutivo.estadoGeneral === 'Saludable') return 'estado-saludable';
        if (this.resumenEjecutivo.estadoGeneral === 'Atención requerida') return 'estado-advertencia';
        if (this.resumenEjecutivo.estadoGeneral === 'Crítico') return 'estado-critico';
        if (this.resumenEjecutivo.estadoGeneral === 'En revisión') return 'estado-advertencia';
        return 'estado-default';
    }

    get claseColorVigencia() {
        console.log('Estado Vigencia:', this.estadoVigencia);
        if (this.estadoVigencia.estado === 'Vigente') return 'vigencia-activa';
        if (this.estadoVigencia.estado === 'Por vencer') return 'vigencia-advertencia';
        if (this.estadoVigencia.estado === 'Vencida') return 'vigencia-vencida';
        return 'vigencia-default';
    }

    get claseColorFinanciero() {
        console.log('Análisis Financiero:', this.analisisFinanciero);
        if (this.analisisFinanciero.alCorriente) return 'financiero-activo';
        if (this.analisisFinanciero.tieneAdeudo) return 'financiero-advertencia';
        if (this.analisisFinanciero.tieneExceso) return 'financiero-info';
        return 'financiero-default';
    }

    get noSearchTerm() { 
        return !this.searchTerm || this.searchTerm.length === 0;
    }
}