public with sharing class CobranzaPolizaController {
    
    @AuraEnabled(cacheable=true)
    public static List<Polizas__c> getPolizas() {
        try {
            return [
                SELECT 
                    Id, 
                    Name, 
                    Asegurado__r.Name, 
                    Estatus__c, 
                    PrimaTotal__c, 
                    Vigencia_hasta__c, 
                    Monto_Proximo_Pago__c,
                    Vigencia_desde__c,
                    Tipo_de_poliza__c,
                    Agente__c
                FROM Polizas__c  
                ORDER BY Vigencia_hasta__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error al obtener pólizas: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getResumenPolizas() {
        Map<String, Integer> resumen = new Map<String, Integer>();
        
        AggregateResult[] resultados = [
            SELECT 
                Estatus__c, 
                COUNT(Id) total
            FROM Polizas__c 
            GROUP BY Estatus__c
        ];
        
        Integer total = 0;
        for (AggregateResult ar : resultados) {
            String estado = (String) ar.get('Estatus__c');
            Integer cantidad = (Integer) ar.get('total');
            resumen.put(estado, cantidad);
            total += cantidad;
        }
        
        resumen.put('totalPolizas', total);
        return resumen;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Pago_Poliza__c> getPagosPoliza(String polizaId) {
        try {
            return [
            SELECT
                Id, 
                Name, 
                Monto__c, 
                Proximo_Pago__c, 
                Fecha_de_Aplicaci_n_del_pago__c, 
                Estatus_pago__c,
                Forma_de_Pago__c
            FROM Pago_Poliza__c 
            WHERE Poliza__c = :polizaId
            ORDER BY Proximo_Pago__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error al obtener pagos: ' + e.getMessage());
        }
    }

    public class ProyeccionCobranzaDTO {
        @AuraEnabled public Id polizaId;
        @AuraEnabled public String numeroPoliza;
        @AuraEnabled public Date fechaEmision;
        @AuraEnabled public Date vigenciaDesde;
        @AuraEnabled public Date vigenciaHasta;
        @AuraEnabled public Date fechaUltimoPago;
        @AuraEnabled public Date fechaEsperadaPago;
        @AuraEnabled public String formaPago;
        @AuraEnabled public Decimal monto;
        @AuraEnabled public String estatusPoliza;
        @AuraEnabled public String aseguradora;
        @AuraEnabled public Id aseguradoId;
        @AuraEnabled public String aseguradoNombre;
        @AuraEnabled public String estatusRecibo;
        @AuraEnabled public Boolean esPagoReal;
        @AuraEnabled public Boolean estaPagado;
        @AuraEnabled public Boolean esPolizaInactiva;
        @AuraEnabled public Boolean esNuevaVigencia;
        @AuraEnabled public Boolean tieneMontoPendiente;
        @AuraEnabled public Boolean tieneMezclaVigencia;
        @AuraEnabled public Boolean tieneArrastre;
        @AuraEnabled public Decimal montoPagadoMXN;
        @AuraEnabled public Decimal montoPendienteMXN;
        @AuraEnabled public Decimal montoProyectadoMXN;
    }

    private class ContextoPago {
        public Polizas__c poliza;
        public Date fechaUltimoPago;
        public Date fechaEsperadaPago;
        public Decimal monto;
        public Boolean esPagoReal;
        public Boolean estaPagado;
        public String estatusRecibo;
        public Boolean esPolizaInactiva;
        public Boolean esNuevaVigencia;
        public Boolean tieneMontoPendiente;
        public Boolean tieneMezclaVigencia;
        public Boolean tieneArrastre;
        public Decimal montoPagadoMXN;
        public Decimal montoPendienteMXN;
        public Decimal montoProyectadoMXN;
    }

    @AuraEnabled(cacheable=false)
    public static List<ProyeccionCobranzaDTO> obtenerProyeccionCobranza(Date fechaDesde, Date fechaHasta) {

        if (fechaDesde == null || fechaHasta == null) {
            throw new AuraHandledException('Debe indicar fecha desde y fecha hasta');
        }

        initRates(Date.today());

        Date todayDate = Date.today();
        Date mesInicioRango = monthKey(fechaDesde);
        Date mesFinRango    = monthKey(fechaHasta);

        List<Polizas__c> polizas = queryPolizas(fechaHasta);
        if (polizas.isEmpty()) return new List<ProyeccionCobranzaDTO>();

        Date minVigenciaDesde = minVigDesde(polizas);
        Date fechaMinPagos = calcFechaMinPagos(fechaDesde, minVigenciaDesde);
        Date fechaMaxPagos = fechaHasta.addMonths(12);

        Map<Id, Date> ultimoPagoPorPoliza = queryUltimoPagoPorPoliza(polizas);

        Map<Id, List<Pago_Poliza__c>> pagosPorPoliza = queryPagosPorPoliza(polizas, fechaMinPagos, fechaMaxPagos);

        List<ProyeccionCobranzaDTO> resultado = new List<ProyeccionCobranzaDTO>();

        for (Polizas__c poliza : polizas) {
            List<Pago_Poliza__c> pagos = pagosPorPoliza.containsKey(poliza.Id) ? pagosPorPoliza.get(poliza.Id) : new List<Pago_Poliza__c>();
            procesarPoliza(poliza, pagos, mesInicioRango, mesFinRango, todayDate, ultimoPagoPorPoliza.get(poliza.Id), resultado);
        }

        return resultado;
    }

    private static List<Polizas__c> queryPolizas(Date fechaHasta) {
        return [
            SELECT Id, Name, Fecha_de_Emision__c, Vigencia_desde__c, Vigencia_hasta__c,
                   Forma_de_pago__c, Prima_Anual__c, Estatus__c, Aseguradora__c,
                   Asegurado__c, Asegurado__r.Name, Moneda__c
            FROM Polizas__c
            WHERE Vigencia_desde__c <= :fechaHasta
              AND Forma_de_pago__c != null
              AND Estatus__c IN ('Vigor', 'Cancelada', 'Vencida', 'Renovada', 'Vigor Prorrogado', 'Se cambio de agente')
        ];
    }

    private static Map<Id, Date> queryUltimoPagoPorPoliza(List<Polizas__c> polizas) {
        Map<Id, Date> res = new Map<Id, Date>();
        for (AggregateResult ar : [
            SELECT Poliza__c polizaId, MAX(Fecha_de_Aplicaci_n_del_pago__c) maxFecha
            FROM Pago_Poliza__c
            WHERE Poliza__c IN :polizas
            GROUP BY Poliza__c
        ]) {
            res.put((Id) ar.get('polizaId'), (Date) ar.get('maxFecha'));
        }
        return res;
    }

    private static Map<Id, List<Pago_Poliza__c>> queryPagosPorPoliza(List<Polizas__c> polizas, Date fechaMinPagos, Date fechaMaxPagos) {
        Map<Id, List<Pago_Poliza__c>> mapa = new Map<Id, List<Pago_Poliza__c>>();
        for (Pago_Poliza__c p : [
            SELECT Id, Poliza__c,
                   Monto__c, Tipo_de_Moneda__c, Valor_Moneda__c,
                   Fecha_de_Aplicaci_n_del_pago__c, Fecha_de_de_Vencimiento__c,
                   Estatus_pago__c
            FROM Pago_Poliza__c
            WHERE Poliza__c IN :polizas
              AND Fecha_de_de_Vencimiento__c != null
              AND Fecha_de_de_Vencimiento__c >= :fechaMinPagos
              AND Fecha_de_de_Vencimiento__c <= :fechaMaxPagos
            ORDER BY Fecha_de_de_Vencimiento__c ASC
        ]) {
            if (!mapa.containsKey(p.Poliza__c)) mapa.put(p.Poliza__c, new List<Pago_Poliza__c>());
            mapa.get(p.Poliza__c).add(p);
        }
        return mapa;
    }

    private static Date minVigDesde(List<Polizas__c> polizas) {
        Date minD = null;
        for (Polizas__c p : polizas) {
            if (p.Vigencia_desde__c == null) continue;
            if (minD == null || p.Vigencia_desde__c < minD) minD = p.Vigencia_desde__c;
        }
        return minD;
    }

    private static Date calcFechaMinPagos(Date fechaDesde, Date minVigenciaDesde) {
        Date d = fechaDesde.addYears(-1);
        if (minVigenciaDesde != null && minVigenciaDesde < d) d = minVigenciaDesde;
        return d;
    }

    private static void procesarPoliza(
        Polizas__c poliza,
        List<Pago_Poliza__c> pagosOriginales,
        Date mesInicioRango,
        Date mesFinRango,
        Date todayDate,
        Date ultimoPago,
        List<ProyeccionCobranzaDTO> out
    ) {
        if (poliza.Vigencia_desde__c == null) return;

        Boolean esPolizaInactiva = (poliza.Estatus__c == 'Cancelada' || poliza.Estatus__c == 'Vencida');

        String monedaPoliza = normalizeCurrencyPoliza(poliza.Moneda__c);
        if (String.isBlank(monedaPoliza)) monedaPoliza = 'MXN';

        Decimal rateHoyPoliza = rateForCurrency(monedaPoliza, todayDate);
        if (rateHoyPoliza == null) rateHoyPoliza = 1;

        List<Pago_Poliza__c> pagos = filtrarCanceladosOVencidosIntermedios(pagosOriginales);

        Decimal primaAnualOriginal = (poliza.Prima_Anual__c != null ? poliza.Prima_Anual__c : 0).setScale(2);

        Date fechaInicioNuevaVig = (poliza.Vigencia_hasta__c != null) ? poliza.Vigencia_hasta__c.addDays(1) : null;
        Date mesNuevaVig = (fechaInicioNuevaVig != null) ? monthKey(fechaInicioNuevaVig) : null;

        Map<Date, MesEstado> estadoPorMes = new Map<Date, MesEstado>();

        Set<Date> mesesConReciboVenc = new Set<Date>();

        Map<Integer, Decimal> existentePorAnio = new Map<Integer, Decimal>();

        Date mesBaseVig = monthKey(poliza.Vigencia_desde__c);

        Date mesCorte = calcularEIngerirPagos(
            pagos,
            poliza,
            monedaPoliza,
            todayDate,
            fechaInicioNuevaVig,
            mesBaseVig,
            estadoPorMes,
            mesesConReciboVenc,
            existentePorAnio
        );

        if (esPolizaInactiva) {
            emitirMeses(poliza, estadoPorMes, mesInicioRango, mesFinRango, ultimoPago, true, false, mesNuevaVig, out);
            return;
        }

        proyectarYArrastrar(
            poliza,
            primaAnualOriginal,
            monedaPoliza,
            rateHoyPoliza,
            mesCorte,
            mesFinRango,
            mesesConReciboVenc,
            existentePorAnio,
            estadoPorMes
        );

        emitirMeses(poliza, estadoPorMes, mesInicioRango, mesFinRango, ultimoPago, false, true, mesNuevaVig, out);
    }

    private class SpillItem {
        public Date mesVenc;
        public Decimal montoEnPoliza;
        public SpillItem(Date mesVenc, Decimal montoEnPoliza) {
            this.mesVenc = mesVenc;
            this.montoEnPoliza = montoEnPoliza;
        }
    }

    private static Date calcularEIngerirPagos(
        List<Pago_Poliza__c> pagos,
        Polizas__c poliza,
        String monedaPoliza,
        Date todayDate,
        Date fechaInicioNuevaVig,
        Date mesBaseVig,
        Map<Date, MesEstado> estadoPorMes,
        Set<Date> mesesConReciboVenc,
        Map<Integer, Decimal> existentePorAnio
    ) {
        Date mesCorte = monthKey(poliza.Vigencia_desde__c).addMonths(-1);
        Date maxMv = null;

        List<SpillItem> spillReales = new List<SpillItem>();

        Date mesRenov = (fechaInicioNuevaVig != null) ? monthKey(fechaInicioNuevaVig) : null;

        for (Pago_Poliza__c p : pagos) {
            if (p.Fecha_de_de_Vencimiento__c == null) continue;

            Date venc = p.Fecha_de_de_Vencimiento__c;
            Date mesVenc = monthKey(venc);

            Boolean esSpillReal = (poliza.Vigencia_hasta__c != null && venc > poliza.Vigencia_hasta__c);

            Boolean esTramoViejoMesRenov = false;
            if (fechaInicioNuevaVig != null && mesRenov != null) {
                if (mesVenc == mesRenov && venc < fechaInicioNuevaVig) {
                    esTramoViejoMesRenov = true;
                }
            }

            Boolean esSpill = (esSpillReal || esTramoViejoMesRenov);

            if (!esSpill) {
                mesesConReciboVenc.add(mesVenc);
            }

            if (!esSpillReal) {
                Date mv = mesVenc;

                if (esTramoViejoMesRenov) {
                    mv = mv.addMonths(-1);
                }

                if (maxMv == null || mv > maxMv) maxMv = mv;
            }

            Decimal montoRecibo = (p.Monto__c != null ? p.Monto__c : 0).setScale(2);

            RateInfo ri = rateInfoForPago(p, todayDate);
            Decimal ratePago = (ri.rate != null ? ri.rate : 1);

            Decimal montoEnPoliza = convertirMontoAMonedaPoliza(montoRecibo, p, monedaPoliza, ri, ratePago);

            if (esSpillReal) {
                spillReales.add(new SpillItem(mesVenc, montoEnPoliza));
            } else {
                Date mesCalculo = mesVenc;

                if (esTramoViejoMesRenov) {
                    mesCalculo = mesVenc.addMonths(-1);
                }

                Integer anioIdx = indiceAnioVigencia(mesBaseVig, mesCalculo);
                sumarDecimalPorEntero(existentePorAnio, anioIdx, montoEnPoliza);
            }

            Decimal montoMXN = (montoRecibo * ratePago).setScale(2);

            Boolean esCanceladoOVencida = (p.Estatus_pago__c == 'Cancelado' || p.Estatus_pago__c == 'Vencida');
            Boolean estaPagado = (p.Fecha_de_Aplicaci_n_del_pago__c != null);

            if (estaPagado) {
                Date mesAplic = monthKey(p.Fecha_de_Aplicaci_n_del_pago__c);
                MesEstado me = getOrCreateMes(estadoPorMes, mesAplic);
                me.montoPagadoMXN += montoMXN;
                me.hayPagado = true;
            } else {
                MesEstado meV = getOrCreateMes(estadoPorMes, mesVenc);

                if (!esCanceladoOVencida) {
                    meV.montoPendienteMXN += montoMXN;
                    meV.hayPendiente = true;
                    if (meV.estatusPendiente == null) meV.estatusPendiente = p.Estatus_pago__c;
                } else {
                    meV.montoCancelVencMXN += montoMXN;
                    meV.hayCancelVenc = true;
                    meV.estatusCancelVenc = escogerCancelVenc(meV.estatusCancelVenc, p.Estatus_pago__c);
                }
            }
        }

        if (maxMv != null) mesCorte = maxMv;

        if (!spillReales.isEmpty() && mesCorte != null) {
            Integer anioCorte = indiceAnioVigencia(mesBaseVig, mesCorte);
            for (SpillItem si : spillReales) {
                sumarDecimalPorEntero(existentePorAnio, anioCorte, si.montoEnPoliza);
            }
        }

        return mesCorte;
    }

    private static Decimal convertirMontoAMonedaPoliza(Decimal montoRecibo, Pago_Poliza__c p, String monedaPoliza, RateInfo ri, Decimal ratePago) {

        String monedaPago = normalizeCurrency(p.Tipo_de_Moneda__c);
        if (String.isBlank(monedaPago)) monedaPago = monedaPoliza;

        if (monedaPago == monedaPoliza) return montoRecibo;

        Decimal ratePolizaRef = rateForCurrency(monedaPoliza, ri.refDate);
        if (ratePolizaRef == null || ratePolizaRef == 0) return montoRecibo;

        return ((montoRecibo * ratePago) / ratePolizaRef).setScale(2);
    }

    private static void proyectarYArrastrar(
        Polizas__c poliza,
        Decimal primaAnualOriginal,
        String monedaPoliza,
        Decimal rateHoyPoliza,
        Date mesCorte,
        Date mesFinRango,
        Set<Date> mesesConReciboVenc,
        Map<Integer, Decimal> existentePorAnio,
        Map<Date, MesEstado> estadoPorMes
    ) {
        Date mesBaseVig = monthKey(poliza.Vigencia_desde__c);

        Date finSchedule = monthKey(mesFinRango.addMonths(12));

        Integer paso = obtenerMesesPorFormaPago(poliza.Forma_de_pago__c);
        if (paso <= 0) paso = 1;

        Integer pagosPorAnio = obtenerPagosPorAnio(poliza.Forma_de_pago__c);
        if (pagosPorAnio <= 0) pagosPorAnio = 1;

        Decimal tol = toleranciaPorMoneda(monedaPoliza);

        Map<Integer, List<Date>> candidatosPorAnio = new Map<Integer, List<Date>>();

        for (Date mesProg = mesBaseVig; mesProg <= finSchedule; mesProg = mesProg.addMonths(paso)) {

            if (mesProg <= mesCorte) continue;

            if (mesesConReciboVenc.contains(mesProg)) continue;

            Integer anioIdx = indiceAnioVigencia(mesBaseVig, mesProg);

            if (!candidatosPorAnio.containsKey(anioIdx)) {
                candidatosPorAnio.put(anioIdx, new List<Date>());
            }
            candidatosPorAnio.get(anioIdx).add(mesProg);
        }

        Integer maxAnioIdx = indiceAnioVigencia(mesBaseVig, finSchedule);

        for (Integer anioIdx = 0; anioIdx <= maxAnioIdx; anioIdx++) {

            Decimal existente = (existentePorAnio.containsKey(anioIdx) ? existentePorAnio.get(anioIdx) : 0).setScale(2);
            Decimal restanteAnio = (primaAnualOriginal - existente).setScale(2);

            if (restanteAnio.abs() <= tol) restanteAnio = 0;
            if (restanteAnio <= 0) continue;

            List<Date> candidatos = candidatosPorAnio.containsKey(anioIdx)
                ? candidatosPorAnio.get(anioIdx)
                : new List<Date>();

            if (!candidatos.isEmpty()) {
                aplicarProyeccionNormal(restanteAnio, candidatos, estadoPorMes, rateHoyPoliza);
                continue;
            }

            Integer cuotasFaltantes = calcularCuotasFaltantesPorMonto(restanteAnio, primaAnualOriginal, pagosPorAnio, tol);

            Date inicioSiguienteAnio = mesBaseVig.addMonths((anioIdx + 1) * 12);

            aplicarArrastre(restanteAnio, cuotasFaltantes, inicioSiguienteAnio, paso, estadoPorMes, rateHoyPoliza, tol, mesCorte);
        }
    }

    private static void aplicarProyeccionNormal(
        Decimal total,
        List<Date> meses,
        Map<Date, MesEstado> estadoPorMes,
        Decimal rateHoyPoliza
    ) {
        Integer n = meses.size();
        Decimal base = (total / n).setScale(2);
        Decimal acum = 0;

        for (Integer i = 0; i < n; i++) {
            Date m = meses[i];
            Decimal monto = (i == n - 1) ? (total - acum).setScale(2) : base;
            if (i != n - 1) acum += base;

            MesEstado me = getOrCreateMes(estadoPorMes, m);

            Decimal actual = (me.montoProyectadoMXN != null) ? me.montoProyectadoMXN : 0;
            me.montoProyectadoMXN = (actual + (monto * rateHoyPoliza)).setScale(2);
            me.hayProyeccion = true;
        }
    }

    private static Integer calcularCuotasFaltantesPorMonto(
        Decimal restanteAnio,
        Decimal primaAnualOriginal,
        Integer pagosPorAnio,
        Decimal tol
    ) {
        if (restanteAnio.abs() <= tol) return 0;

        Decimal cuotaTeorica = (primaAnualOriginal / pagosPorAnio).setScale(2);
        if (cuotaTeorica <= 0) cuotaTeorica = primaAnualOriginal;

        Integer cuotas = (Integer)Math.ceil((restanteAnio / cuotaTeorica).doubleValue());
        if (cuotas <= 0) cuotas = 1;

        return cuotas;
    }

    private static void aplicarArrastre(
        Decimal restanteAnio,
        Integer cuotasFaltantes,
        Date inicioSiguienteAnio,
        Integer paso,
        Map<Date, MesEstado> estadoPorMes,
        Decimal rateHoyPoliza,
        Decimal tol,
        Date mesCorte
    ) {
        if (cuotasFaltantes == null || cuotasFaltantes <= 0) return;
        if (inicioSiguienteAnio == null) return;

        Decimal base = (restanteAnio / cuotasFaltantes).setScale(2);

        Date cursor = inicioSiguienteAnio;
        Decimal restante = restanteAnio.setScale(2);

        if (mesCorte != null) {
            while (cursor <= mesCorte) {
                cursor = cursor.addMonths(paso);
            }
        }

        for (Integer i = 0; i < cuotasFaltantes; i++) {

            cursor = avanzarHastaMesLibre(cursor, paso, estadoPorMes);

            if (mesCorte != null) {
                while (cursor <= mesCorte) {
                    cursor = cursor.addMonths(paso);
                    cursor = avanzarHastaMesLibre(cursor, paso, estadoPorMes);
                }
            }

            Decimal cuota = (i == cuotasFaltantes - 1) ? restante : Math.min(base, restante);

            MesEstado me = getOrCreateMes(estadoPorMes, cursor);
            me.montoArrastreMXN += (cuota * rateHoyPoliza).setScale(2);
            me.hayArrastre = true;

            restante = (restante - cuota).setScale(2);
            cursor = cursor.addMonths(paso);

            if (restante.abs() <= tol) break;
        }
    }

    private static Date avanzarHastaMesLibre(Date cursor, Integer paso, Map<Date, MesEstado> estadoPorMes) {
        while (mesTieneReal(estadoPorMes.get(cursor))) {
            cursor = cursor.addMonths(paso);
        }
        return cursor;
    }

    private static Boolean mesTieneReal(MesEstado me) {
        if (me == null) return false;
        if (me.hayPagado && me.montoPagadoMXN > 0) return true;
        if (me.hayPendiente && me.montoPendienteMXN > 0) return true;
        if (me.hayCancelVenc && me.montoCancelVencMXN > 0) return true;
        return false;
    }

    private static Integer obtenerPagosPorAnio(String formaPago) {
        if (formaPago == null) return 1;

        switch on formaPago.toLowerCase() {
            when 'mensual'    { return 12; }
            when 'trimestral' { return 4; }
            when 'semestral'  { return 2; }
            when 'anual'      { return 1; }
            when 'unica'      { return 1; }
            when else         { return 1; }
        }
    }

    private static Decimal toleranciaPorMoneda(String monedaPoliza) {
        if (String.isBlank(monedaPoliza)) return 0.1;
        String m = monedaPoliza.trim().toUpperCase();
        if (m == 'UDI') return 1;
        return 0.1;
    }

    private static void emitirMeses(
        Polizas__c poliza,
        Map<Date, MesEstado> estadoPorMes,
        Date mesInicioRango,
        Date mesFinRango,
        Date ultimoPago,
        Boolean esPolizaInactiva,
        Boolean permitirProyeccion,
        Date mesNuevaVig,
        List<ProyeccionCobranzaDTO> out
    ) {

        if (estadoPorMes == null || estadoPorMes.isEmpty()) return;

        List<Date> meses = new List<Date>(estadoPorMes.keySet());
        meses.sort();

        for (Date mes : meses) {
            if (mes < mesInicioRango || mes > mesFinRango) continue;

            MesEstado me = estadoPorMes.get(mes);
            if (me == null) continue;

            ContextoPago ctx = construirContextoDesdeMes(
                poliza, me, mes, ultimoPago,
                esPolizaInactiva, permitirProyeccion, mesNuevaVig
            );

            if (ctx != null) out.add(crearDTO(ctx));
        }
    }

    private static ContextoPago construirContextoDesdeMes(
        Polizas__c poliza,
        MesEstado me,
        Date mes,
        Date fechaUltimoPago,
        Boolean esPolizaInactiva,
        Boolean permitirProyeccion,
        Date mesNuevaVig
    ) {
        ContextoPago ctx = new ContextoPago();
        ctx.poliza = poliza;
        ctx.fechaUltimoPago = fechaUltimoPago;
        ctx.fechaEsperadaPago = mes;
        ctx.esPolizaInactiva = esPolizaInactiva;
        ctx.esNuevaVigencia = (mesNuevaVig != null) ? (mes >= mesNuevaVig) : false;

        ctx.tieneMontoPendiente = false;
        ctx.tieneMezclaVigencia = false;
        ctx.tieneArrastre = false;

        Decimal pagadoMXN    = (me.hayPagado     && me.montoPagadoMXN     != null) ? me.montoPagadoMXN     : 0;
        Decimal pendienteMXN = (me.hayPendiente  && me.montoPendienteMXN  != null) ? me.montoPendienteMXN  : 0;
        Decimal cancelMXN    = (me.hayCancelVenc && me.montoCancelVencMXN != null) ? me.montoCancelVencMXN : 0;
        Decimal proyMXN      = (me.hayProyeccion && me.montoProyectadoMXN != null) ? me.montoProyectadoMXN : 0;
        Decimal arrastreMXN  = (me.hayArrastre   && me.montoArrastreMXN   != null) ? me.montoArrastreMXN   : 0;

        ctx.tieneArrastre = (arrastreMXN > 0);
        Boolean enNuevaVig = (mesNuevaVig != null) ? (mes >= mesNuevaVig) : false;
        Boolean hayProy = permitirProyeccion && (proyMXN > 0);

        Boolean hayPagado = (pagadoMXN > 0);
        Boolean hayPend   = (pendienteMXN > 0);
        Boolean hayCancel = (cancelMXN > 0);

        Boolean hayReal = hayPagado || hayPend || hayCancel;

        ctx.montoPagadoMXN = pagadoMXN.setScale(2);
        ctx.montoPendienteMXN = (pendienteMXN + cancelMXN).setScale(2);
        ctx.montoProyectadoMXN = (proyMXN + arrastreMXN).setScale(2);

        if (enNuevaVig && hayProy && hayReal) {
            Decimal realMXN = 0;

            if (hayPagado) realMXN += pagadoMXN;
            if (hayPend)   realMXN += pendienteMXN;

            if (realMXN == 0 && hayCancel) realMXN = cancelMXN;

            ctx.monto = (realMXN + proyMXN + arrastreMXN).setScale(2);
            ctx.esPagoReal = true;
            ctx.estaPagado = hayPagado;
            ctx.estatusRecibo = hayPagado
                ? 'Pagado'
                : (hayPend ? me.estatusPendiente : me.estatusCancelVenc);

            ctx.tieneMontoPendiente = hayPend;
            ctx.tieneMezclaVigencia = true;
            ctx.esNuevaVigencia = true;

            return ctx;
        }

        if (hayPagado && hayPend) {
            ctx.monto = (pagadoMXN + pendienteMXN + arrastreMXN).setScale(2);
            ctx.esPagoReal = true;
            ctx.estaPagado = true;
            ctx.estatusRecibo = 'Pagado';
            ctx.tieneMontoPendiente = true;
            return ctx;
        }

        if (hayPagado) {
            ctx.monto = (pagadoMXN + arrastreMXN).setScale(2);
            ctx.esPagoReal = true;
            ctx.estaPagado = true;
            ctx.estatusRecibo = 'Pagado';
            return ctx;
        }

        if (hayPend) {
            ctx.monto = (pendienteMXN + arrastreMXN).setScale(2);
            ctx.esPagoReal = true;
            ctx.estaPagado = false;
            ctx.estatusRecibo = me.estatusPendiente;
            return ctx;
        }

        if (hayCancel) {
            ctx.monto = (cancelMXN + arrastreMXN).setScale(2);
            ctx.esPagoReal = true;
            ctx.estaPagado = false;
            ctx.estatusRecibo = me.estatusCancelVenc;
            return ctx;
        }

        if (hayProy) {
            ctx.monto = (proyMXN + arrastreMXN).setScale(2);
            ctx.esPagoReal = false;
            ctx.estaPagado = false;
            ctx.estatusRecibo = 'Pendiente';
            return ctx;
        }

        if (arrastreMXN > 0) {
            ctx.monto = arrastreMXN.setScale(2);
            ctx.esPagoReal = false;
            ctx.estaPagado = false;
            ctx.estatusRecibo = 'Pendiente';
            return ctx;
        }

        return null;
    }

    private static Integer obtenerMesesPorFormaPago(String formaPago) {
        if (formaPago == null) return 0;

        switch on formaPago.toLowerCase() {
            when 'mensual'    { return 1; }
            when 'trimestral' { return 3; }
            when 'semestral'  { return 6; }
            when 'anual'      { return 12; }
            when 'unica'      { return 0; }
            when else         { return 0; }
        }
    }

    private class MesEstado {
        public Decimal montoPagadoMXN     = 0;
        public Decimal montoPendienteMXN  = 0;
        public Decimal montoCancelVencMXN = 0;
        public Decimal montoProyectadoMXN = null;

        public Boolean hayPagado    = false;
        public Boolean hayPendiente = false;
        public Boolean hayCancelVenc= false;
        public Boolean hayProyeccion= false;

        public String estatusPendiente = null;
        public String estatusCancelVenc = null;

        public Decimal montoArrastreMXN = 0;
        public Boolean hayArrastre = false;
    }

    private static MesEstado getOrCreateMes(Map<Date, MesEstado> mapa, Date mes) {
        MesEstado me = mapa.get(mes);
        if (me == null) {
            me = new MesEstado();
            mapa.put(mes, me);
        }
        return me;
    }

    private static String escogerCancelVenc(String actual, String nuevo) {
        if (String.isBlank(actual)) return nuevo;
        if (actual == 'Cancelado' || nuevo == 'Cancelado') return 'Cancelado';
        return 'Vencida';
    }

    private static Date monthKey(Date d) {
        if (d == null) return null;
        return Date.newInstance(d.year(), d.month(), 1);
    }

    private static List<Pago_Poliza__c> filtrarCanceladosOVencidosIntermedios(List<Pago_Poliza__c> pagosOrdenadosPorVenc) {
        List<Pago_Poliza__c> pagos = new List<Pago_Poliza__c>();
        if (pagosOrdenadosPorVenc == null || pagosOrdenadosPorVenc.isEmpty()) return pagos;

        Pago_Poliza__c ultimo = pagosOrdenadosPorVenc[pagosOrdenadosPorVenc.size() - 1];

        for (Pago_Poliza__c p : pagosOrdenadosPorVenc) {
            Boolean esCanceladoOVencido = (p.Estatus_pago__c == 'Cancelado' || p.Estatus_pago__c == 'Vencida');
            if (esCanceladoOVencido && p.Id != ultimo.Id) continue;
            pagos.add(p);
        }
        return pagos;
    }

    private static List<Date> generarMesesProgramados(Date vigDesde, Date hasta, String formaPago) {
        List<Date> meses = new List<Date>();
        if (vigDesde == null || hasta == null || formaPago == null) return meses;

        Date mesActual = monthKey(vigDesde);
        Date mesHasta  = monthKey(hasta);

        if (formaPago.toLowerCase() == 'unica') {
            if (mesActual <= mesHasta) meses.add(mesActual);
            return meses;
        }

        Integer paso = obtenerMesesPorFormaPago(formaPago);
        if (paso <= 0) return meses;

        while (mesActual <= mesHasta) {
            meses.add(mesActual);
            mesActual = mesActual.addMonths(paso);
        }
        return meses;
    }

    private static Integer indiceAnioVigencia(Date mesBaseVig, Date mes) {
        if (mesBaseVig == null || mes == null) return 0;
        Integer diff = mesBaseVig.monthsBetween(mes);
        if (diff < 0) diff = 0;
        return diff / 12;
    }

    private static void sumarDecimalPorFecha(Map<Date, Decimal> mapa, Date key, Decimal valor) {
        if (mapa == null || key == null || valor == null) return;
        mapa.put(key, (mapa.containsKey(key) ? mapa.get(key) : 0) + valor);
    }

    private static void sumarDecimalPorEntero(Map<Integer, Decimal> mapa, Integer key, Decimal valor) {
        if (mapa == null || key == null || valor == null) return;
        mapa.put(key, (mapa.containsKey(key) ? mapa.get(key) : 0) + valor);
    }

    private static ProyeccionCobranzaDTO crearDTO(ContextoPago ctx) {
        ProyeccionCobranzaDTO dto = new ProyeccionCobranzaDTO();

        dto.polizaId = ctx.poliza.Id;
        dto.numeroPoliza = ctx.poliza.Name;
        dto.fechaEmision = ctx.poliza.Fecha_de_Emision__c;
        dto.vigenciaDesde = ctx.poliza.Vigencia_desde__c;
        dto.vigenciaHasta = ctx.poliza.Vigencia_hasta__c;
        dto.fechaUltimoPago = ctx.fechaUltimoPago;
        dto.fechaEsperadaPago = ctx.fechaEsperadaPago;
        dto.formaPago = ctx.poliza.Forma_de_pago__c;
        dto.monto = ctx.monto;
        dto.estatusPoliza = ctx.poliza.Estatus__c;
        dto.aseguradora = ctx.poliza.Aseguradora__c;
        dto.aseguradoId = ctx.poliza.Asegurado__c;
        dto.aseguradoNombre = ctx.poliza.Asegurado__r != null ? ctx.poliza.Asegurado__r.Name : null;
        dto.tieneMezclaVigencia = (ctx.tieneMezclaVigencia == null) ? false : ctx.tieneMezclaVigencia;
        dto.tieneArrastre = (ctx.tieneArrastre == null) ? false : ctx.tieneArrastre;

        if (ctx.esPagoReal) {
            Set<String> estadosValidos = new Set<String>{'Pagado', 'Cancelado', 'Vencida'};
            dto.estatusRecibo = estadosValidos.contains(ctx.estatusRecibo) ? ctx.estatusRecibo : 'Pendiente';
        } else {
            dto.estatusRecibo = 'Pendiente';
        }

        dto.esPagoReal = ctx.esPagoReal;
        dto.estaPagado = ctx.estaPagado;
        dto.esPolizaInactiva = ctx.esPolizaInactiva;
        dto.esNuevaVigencia = ctx.esNuevaVigencia;

        dto.tieneMontoPendiente = (ctx.tieneMontoPendiente == null) ? false : ctx.tieneMontoPendiente;

        dto.montoPagadoMXN = (ctx.montoPagadoMXN == null) ? 0 : ctx.montoPagadoMXN;
        dto.montoPendienteMXN = (ctx.montoPendienteMXN == null) ? 0 : ctx.montoPendienteMXN;
        dto.montoProyectadoMXN = (ctx.montoProyectadoMXN == null) ? 0 : ctx.montoProyectadoMXN;

        return dto;
    }

    private static Map<String, List<Exchange_Rate_History__c>> ratesByCurrency;

    private class RateInfo {
        public String currencyPagoPoliza;
        public Decimal rate;
        public Date refDate;
    }

    private static void initRates(Date todayDate) {
        ratesByCurrency = new Map<String, List<Exchange_Rate_History__c>>();

        List<Exchange_Rate_History__c> rates = [
            SELECT CurrencyType__c, RateValue__c, RateDate__c
            FROM Exchange_Rate_History__c
            WHERE CurrencyType__c IN ('UDI','UDIS','USD')
            AND RateDate__c <= :todayDate
            ORDER BY CurrencyType__c, RateDate__c DESC
        ];

        for (Exchange_Rate_History__c r : rates) {
            String key = normalizeCurrency(r.CurrencyType__c);
            if (String.isBlank(key)) continue;

            if (!ratesByCurrency.containsKey(key)) {
                ratesByCurrency.put(key, new List<Exchange_Rate_History__c>());
            }
            ratesByCurrency.get(key).add(r);
        }
    }

    private static Decimal rateForCurrency(String moneda, Date targetDate) {
        if (String.isBlank(moneda)) return 1;
        String m = moneda.trim().toUpperCase();
        if (m == 'MXN') return 1;

        m = normalizeCurrency(m);

        if (ratesByCurrency == null || !ratesByCurrency.containsKey(m)) return null;

        for (Exchange_Rate_History__c r : ratesByCurrency.get(m)) {
            if (r.RateDate__c <= targetDate) return r.RateValue__c;
        }
        return null;
    }

    private static RateInfo rateInfoForPago(Pago_Poliza__c p, Date todayDate) {
        RateInfo ri = new RateInfo();
        ri.currencyPagoPoliza = normalizeCurrency(p.Tipo_de_Moneda__c);
        if (String.isBlank(ri.currencyPagoPoliza)) ri.currencyPagoPoliza = 'MXN';

        Date ref = todayDate;

        if (p.Estatus_pago__c == 'Pagado') {
            if (p.Fecha_de_Aplicaci_n_del_pago__c != null) ref = p.Fecha_de_Aplicaci_n_del_pago__c;
        } else if (p.Estatus_pago__c == 'Pendiente') {
            ref = todayDate;
        } else if (p.Estatus_pago__c == 'Cancelado' || p.Estatus_pago__c == 'Vencida') {
            ref = (p.Fecha_de_de_Vencimiento__c != null) ? p.Fecha_de_de_Vencimiento__c : todayDate;
        } else {
            ref = todayDate;
        }

        ri.refDate = ref;

        if (p.Valor_Moneda__c != null) {
            ri.rate = p.Valor_Moneda__c;
            return ri;
        }

        Decimal computed = rateForCurrency(ri.currencyPagoPoliza, ref);
        ri.rate = (computed != null ? computed : 1);
        return ri;
    }

    private static String normalizeCurrency(String moneda) {
        if (moneda == null) return null;
        moneda = moneda.trim().toUpperCase();
        if (moneda == 'UDIS') return 'UDI';
        return moneda;
    }

    private static String normalizeCurrencyPoliza(String moneda) {
        if (moneda == null) return null;
        moneda = moneda.trim().toUpperCase();

        if (moneda == 'UDIS') return 'UDI';
        if (moneda == 'DLLS') return 'USD';
        if (moneda == 'PESOS') return 'MXN';

        return moneda;
    }
}