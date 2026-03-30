@RestResource(urlMapping='/polizas/*')
global with sharing class PolizaService {

    @HttpPost
    global static String updatePoliza() {
        RestRequest req = RestContext.request;
        String body = req.requestBody.toString();
        System.debug('📩 JSON recibido: ' + body);

        try {
            // 1️⃣ Parsear el JSON al wrapper
            PolizaWrapper wrapper = (PolizaWrapper) JSON.deserialize(body, PolizaWrapper.class);
            System.debug('🔍 Wrapper deserializado: ' + JSON.serialize(wrapper));
			System.debug('🔍 Asegurados en wrapper: ' + wrapper.asegurados);
			System.debug('🔍 Histórico en wrapper: ' + wrapper.historico_aportaciones);
            if (wrapper == null || String.isBlank(wrapper.poliza)) {
                System.debug('El cuerpo del request o el número de póliza está vacío.');
            }

            System.debug('📦 Buscando póliza para actualizar: ' + wrapper.poliza);

            // 2️⃣ Buscar póliza existente (OBLIGATORIO)
            List<Polizas__c> existing = [
                SELECT Id, Name, Numero_Polizas__c
                FROM Polizas__c
                WHERE Name = :wrapper.poliza
                LIMIT 1
            ];

            Polizas__c pol;
            if (!existing.isEmpty()) {
                pol = existing[0];
                System.debug('🔄 Actualizando póliza existente: ' + pol.Id);
            } else {
                System.debug('❌ Error no existe la póliza');
            }


            System.debug('🔄 Actualizando póliza existente: ' + pol.Id);

            // 3️⃣ Mapear campos actualizables de la póliza
            // NO actualizar campos clave como Name o Numero_Polizas__c
            pol.Numero_Polizas__c = wrapper.numeroPolizas;
            pol.Aseguradora__c = wrapper.aseguradora;
            pol.Ramo__c = wrapper.tipo_seguro;
            pol.Plan_Producto__c = wrapper.plan;
            pol.Estatus__c = wrapper.estatus;
            pol.Suma_Aseguradora__c = wrapper.suma_asegurada;
            pol.Moneda__c = wrapper.moneda;
            pol.Forma_de_pago__c = wrapper.forma_pago;
            pol.Agente__c = wrapper.agente;
            pol.Nombre_contratante__c = wrapper.contratante;
            
            if (!String.isBlank(wrapper.fecha_emision)) {
                pol.Fecha_de_Emision__c = parseDateSafe(wrapper.fecha_emision);
            }

            System.debug('✅ Póliza: ' + pol);
            // 4️⃣ Actualizar solo la póliza
            
            try {
                upsert pol;
            	System.debug('✅ Póliza creada/actualizada: ' + pol.Id);
                
                pol = [SELECT Id, Name, Numero_Polizas__c FROM Polizas__c WHERE Id = :pol.Id LIMIT 1];
            	System.debug('🔁 Póliza consultada, Id confirmado: ' + pol.Id);
            }catch (Exception e) {
                System.debug('❌ Error actualizando la póliza: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            }

            // 5️⃣ Opcional: Actualizar asegurados existentes
            if (wrapper.asegurados != null && !wrapper.asegurados.isEmpty()) {
                // updateAsegurados(pol.Id, wrapper.asegurados);
            }

            // 6️⃣ Opcional: Actualizar histórico de aportaciones y pagos
            if (wrapper.historico_aportaciones != null && !wrapper.historico_aportaciones.isEmpty()) {
                // updateHistoricoAportaciones(pol.Id, wrapper.historico_aportaciones);
            }

            // 7️⃣ Respuesta exitosa
            return JSON.serialize(new Map<String, String>{
                'status' => 'success',
                'message' => 'Póliza actualizada correctamente',
                'polizaId' => pol.Id
            });

        } catch (Exception e) {
            System.debug('❌ Error actualizando la póliza: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            RestContext.response.statusCode = 400;
            return JSON.serialize(new Map<String, String>{
                'status' => 'error',
                'message' => e.getMessage()
            });
        }
    }

    // 🔹 Método para actualizar asegurados
    // private static void updateAsegurados(String polizaId, List<PolizaWrapper.AseguradoWrapper> aseguradosWrappers) {
    //     System.debug('🎯 Entrando a updateAsegurados, cantidad: ' + aseguradosWrappers.size());
    //     try {
    //         List<Asegurado__c> aseguradosToUpdate = new List<Asegurado__c>();
            
    //         for (PolizaWrapper.AseguradoWrapper a : aseguradosWrappers) {
    //             if (String.isBlank(a.nombre)) continue;

    //             Asegurado__c aseg = new Asegurado__c(
    //                 Polizas__c = polizaId,
    //                 Name = a.nombre
    //             );

    //             if (!String.isBlank(a.fecha_nacimiento)) {
    //                 aseg.FechaNacimiento__c = parseDateSafe(a.fecha_nacimiento);
    //             }

    //             aseguradosToUpdate.add(aseg);
    //         }

    //         if (!aseguradosToUpdate.isEmpty()) {
    //             upsert aseguradosToUpdate;
    //             System.debug('✅ ' + aseguradosToUpdate.size() + ' asegurados actualizados.');
    //         }
    //     } catch (Exception e) {
    //         System.debug('⚠️ Error actualizando asegurados: ' + e.getMessage());
    //         // No lanzar excepción para no interrumpir la actualización principal
    //     }
    // }

    // // 🔹 Método para actualizar histórico de aportaciones
    // private static void updateHistoricoAportaciones(String polizaId, List<PolizaWrapper.HistoricoAportacionWrapper> historicosWrappers) {
    //     System.debug('🎯 Entrando a updateHistoricoAportaciones, cantidad: ' + historicosWrappers.size());
    //     try {
    //         List<Historico_Aportacion__c> historicosToUpdate = new List<Historico_Aportacion__c>();
    //         List<Pago_poliza__c> pagosToUpdate = new List<Pago_poliza__c>();

    //         for (PolizaWrapper.HistoricoAportacionWrapper h : historicosWrappers) {
    //             Historico_Aportacion__c hist = new Historico_Aportacion__c(
    //                 Poliza__c = polizaId,
    //                 Anualidad__c = h.anualidad,
    //                 PrimaBasica__c = h.prima_basica,
    //                 PrimaAdicional__c = h.prima_adicional,
    //                 PagosIngresados__c = h.pagos_ingresados
    //             );

    //             if (!String.isBlank(h.desde)) hist.Desde__c = parseDateSafe(h.desde);
    //             if (!String.isBlank(h.hasta)) hist.Hasta__c = parseDateSafe(h.hasta);

    //             upsert hist; // Insertar o actualizar histórico

    //             // Actualizar pagos asociados
    //             if (h.detalle_ingresos != null && !h.detalle_ingresos.isEmpty()) {
    //                 for (PolizaWrapper.PagosPolizaWrapper d : h.detalle_ingresos) {
    //                     Pago_poliza__c pago = new Pago_poliza__c(
    //                         Historico_Aportacion__c = hist.Id,
    //                         Poliza__c = polizaId,
    //                         Tipo_de_Moneda__c = d.Moneda,
    //                         Modo_de_Pago__c = d.Tipo_de_pago,
    //                         Folio__c = d.No_cuenta_No_cheque
    //                     );

    //                     if (!String.isBlank(d.Fecha_de_ingreso)) pago.Fecha_de_emision__c = parseDateSafe(d.Fecha_de_ingreso);
    //                     if (d.Importe_pagado != null) pago.Importe_de_Ultima_Aportacion__c = d.Importe_pagado;
    //                     if (d.Tipo_cambio_del_pago != null) pago.Valor_Moneda__c = d.Tipo_cambio_del_pago;
    //                     if (d.Importe_USD != null) pago.Pago_en_Moneda__c = d.Importe_USD;

    //                     pagosToUpdate.add(pago);
    //                 }
    //             }
    //         }

    //         if (!pagosToUpdate.isEmpty()) {
    //             upsert pagosToUpdate;
    //             System.debug('✅ ' + pagosToUpdate.size() + ' pagos actualizados.');
    //         }
    //     } catch (Exception e) {
    //         System.debug('⚠️ Error actualizando histórico de aportaciones: ' + e.getMessage());
    //         // No lanzar excepción para no interrumpir la actualización principal
    //     }
    // }

    // 🔹 Método auxiliar para fechas seguras
    public static Date parseDateSafe(String input) {
        try {
            String normalized = input.replace('/', '-');
            return Date.valueOf(normalized);
        } catch (Exception e) {
            System.debug('⚠️ Fecha inválida: ' + input);
            return null;
        }
    }
}