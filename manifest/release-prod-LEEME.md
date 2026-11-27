# Liberación a PROD: Sitio de Empresas e Insurance Policy, sin Cobranza ni Claims

- **Rama:** `release/prod-sitio-empresas`, hecha a partir de `Siniestros-en-Claims` en el commit `ae656d1`.
- **Manifiesto:** `manifest/release-prod.xml`, con 630 componentes y API 68.0.
- **Contenido:** solo lo que va a PROD.
  - Lo nuevo de Cobranza y Claims se borró de la rama.
  - Lo que Cobranza o Claims modificaron regresó a la versión de PROD (`main`).
  - Los objetos estándar que solo traían diferencias de UAT también regresaron a la versión de PROD.

> - **No unir esta rama a `develop` ni a `Siniestros-en-Claims`:** les borraría Cobranza y Claims.
> - **No desplegarla a DEV ni a UAT:** les quitaría los pagos, la cobranza y Nuevo siniestro.
> - **Para revisarla se valida sin desplegar.** A esas validaciones no hay que hacerles Quick Deploy en UAT.

## Qué lleva

| Tipo | Cantidad | Tipo | Cantidad |
|---|---|---|---|
| Campos | 362 | Tipos de registro | 14 |
| Clases Apex | 79 (40 de prueba) | Reglas de validación | 14 |
| Componentes LWC | 36 | Flujos | 11 |
| Documentos (logos de correos) | 16 | Prompts de IA | 10 |
| Formatos de página | 16 | Vistas de lista | 10 |
| Objetos (los 5 nuevos, Póliza y Cobertura de producto) | 7 | Formatos compactos | 8 |
| Plantillas de correo (carpeta Empresas) | 7 | Conjuntos de permisos | 5 |
| Perfiles (solo lo nuevo) | 4 | Listas de valores (globales 4, estándar 4) | 8 |
| Otros (páginas VF, triggers, proceso de ventas, permisos, pestaña, páginas, menú, acciones, etc.) | 23 | **Total** | **630** |

Esto cubre:
- Pólizas empresariales: asegurados, vehículos y ubicaciones, movimientos, solicitudes, seguimiento y correos a asegurados.
- Crear Póliza y Crear Oportunidad, con el comparativo.
- Gestión comercial.
- Vigencias, renovación y avisos.
- El Sitio de Empresas: controladores, LWC y menú de navegación.

## Qué queda fuera

- **Cobranza:**
  - Pagos y pólizas de MuleSoft, planes de pago y cuotas, conciliación y estatus de la aseguradora.
  - Reporte Cartera vencida.
  - Permisos `Cobranza_*` y `MuleSoft_*`.
  - Triggers de pagos y de la póliza.
  - Los flujos `Bloquear_Closed_Won_Sin_Pago_Reconocido` y `Cerrada_Ganada_Automatico`; este último se queda en PROD como está.
  - Los conjuntos de valores `IPolicy*`.
- **Claims:**
  - Tipos de registro, campos, páginas y rutas de Claim.
  - Nuevo siniestro y los avisos de siniestros.
  - Los reportes de Siniestros.
  - Los permisos `Siniestros_*`.
- **Piezas mixtas:**
  - Los campos `collectionPaymentStatus__c`, `collectionNextDueDate__c` y `sourceIsCollective__c`.
  - La regla `PremiumFieldsRequired` y el tipo de registro `Insurance_Policy` de la póliza.
  - La página `P_liza_de_registro`.
  - Las clases sin uso `PdfOpportunityController` (con su prueba) y `QuoteComparisonController`.
- **Configuración de los objetos estándar** Cuenta, Contacto, Oportunidad, Cuenta persona, Producto, Cotización, Rol de contacto de oportunidad y Partida de cotización. Era el estado de UAT encima del de PROD:
  - Cambiaba la compartición de Cuenta, Contacto y Oportunidad a Privado o controlada por la cuenta.
  - A la Oportunidad le quitaba su página asignada y el historial de campos.
  - Sus campos, tipos de registro, vistas y reglas sí van, por separado.
- **Las 4 reglas de duplicados y las reglas de coincidencia de Contacto y Cuenta persona:** son las estándar, traídas de UAT en mayo, sin cambios nuestros.

## Piezas de Cobranza que sí van

Lo nuestro las usa y no tienen lógica de cobranza:
- Los campos del vehículo en CustomerProperty: `Carroceria__c`, `Color__c`, `Motor__c`, `Servicio__c`, `TarifaAseguradora__c`, `TipoVehiculo__c` y `Uso__c`.
- El conjunto de permisos `Vehiculos_FSC`.
- Los campos de la póliza `nextPolicy__c` y `termPeriod__c`.
- La acción `InsurancePolicy.Enviar_Correo`.
- El permiso `Senalar_Oportunidad_Por_Reversa`.

## Ajustes hechos en esta rama

**Sin Cobranza ni Claims**

| Pieza | Ajuste |
|---|---|
| `PortalPolizasController` y `PortalPolizasPestanas` | Ya no leen cuotas ni campos de Cobranza; el Dashboard manda `conPagos` en false y Pagos regresa sin cuotas |
| LWC `portalPolizas`, `portalDashboard` y `portalInicio`, y el menú del sitio | Sin la pestaña Pagos, sin Por pagar, Vencido ni Pagado, sin las gráficas ni la lista de pagos, sin el acceso a Pagos ni la opción Pagos del menú |
| LWC `movimientosColectivo`, `movimientosFlotilla` y `movimientosUbicaciones` | Sin el botón ni la ventana de Nuevo siniestro |
| Página `Insurance_Policy_Record_Page` | Sin las pestañas Pagos y Siniestros, sin las secciones Cobranza y Prima desalineada, y sin los campos de la aseguradora |
| Formato, formato compacto y vista de la póliza | Sin las secciones, campos y listas relacionadas de Cobranza |
| `AvisoRenovacionPoliza` | «Vigente» y «Cancelado» directos, sin `PolicyStatusService` |
| 3 pruebas que usaban `CollectionsTestDataFactory` | Usan la clase nueva `DatosPruebaPolizas`, sin planes de pago |
| Pruebas del sitio | Comprueban que sin Cobranza no haya pagos |
| Perfiles `Admin` y los 3 de comunidad | Solo lo nuevo: acceso a las 4 clases del sitio (comunidad) y 3 campos (Admin) |

**Para que el paquete se pueda desplegar**

Esto lo encontró la validación en UAT.

| Pieza | Ajuste |
|---|---|
| Tipos de registro `Oportunidades`, `Oportunidad_Colectiva`, `Oportunidad_Individual`, `Product` y `Quote` | Tenían el XML mal cerrado desde que se agregó el ramo Mascotas (26/10); ya no se podían desplegar. Corregido |
| Esos mismos tipos de registro | Se quitaron los valores que ya no existen en la definición de su campo; por ejemplo, «Ahorro» en Ramo y «Amistad» en Mercado |
| Tipo de registro `Insurance_Policy_Asset` | Sin el formato compacto `Insurance_Policy_Asset`, que no existe |
| Formato de Cuenta persona | Sin el botón `ScheduleAppointment`, que no existe |
| Reglas `Business_Account`, `Person_Account` y `Phone_Format` (Cuenta), y `Bloqueo_quotes_si_existe_aceptada`, `No_change_status` y `No_permite_aceptado` (Cotización) | Inactivas, como en UAT, donde se probó todo; en el repositorio venían activas |
| Manifiesto | API 68.0: el flujo `Set_PriceBook` está guardado en 68.0 |

El LWC `portalPagos` va en el paquete porque compila, pero no se llega a él desde el sitio. No hay que crear la página «mis-pagos» en el sitio de PROD.

## Decisiones de Avanza antes del día D

1. **Listas rediseñadas en Gestión comercial.** El paquete trae las listas como están en UAT. En PROD esto quitaría valores que seguramente usan registros existentes:
   - Mercado de la oportunidad: de 23 valores a 7, con los nuevos Corporativo, Gobierno, Individual y PyME.
   - Plan producto: de 127 valores a 1.
   - Categoría GMM, Vida, Dentegra y Adicional del contacto: sin «06».
   - Ramo y Familia de producto, que reemplazan la lista completa de PROD. En UAT, Ramo además tiene «Salud», que no está en el repositorio.
   - Hay que elegir entre:
     - adoptar las listas nuevas y migrar los registros con valores viejos, o
     - conservar los valores viejos en los campos y que los tipos de registro solo muestren los nuevos.
2. **Etapas de la oportunidad.** El proceso de ventas «Pólizas» lleva las etapas de PROD («Necesidad», «Propuesta», «Cierre», «Emitido») más «Gestion Comercial» y «En proceso de emision». Esas dos hay que crearlas en PROD antes de desplegar. UAT ya solo tiene 5 etapas; decidir si las viejas se quedan.
3. **Las 6 reglas de validación** que van apagadas: decidir si se activan en PROD. Si se activan, crear cuentas y cotizaciones va a pedir esos datos.

## Fuera del paquete

- **Carpeta de plantillas «Empresas»:** crearla en PROD antes de desplegar.
- **Etapas nuevas de la oportunidad:** «Gestion Comercial» y «En proceso de emision» (punto 2).
- **El sitio Avanza Empresas:**
  - Experience Cloud, sus páginas sin «mis-pagos» y su usuario invitado.
  - Las licencias Partner Community.
  - Los 3 procesos programados.
  - Las asignaciones de permisos.
- **Frecuencia de prima:** confirmar en PROD los valores que usa Crear Póliza (Mensual, Quincenal, Trimestral, Semestral, Anual).
- **Plantillas «Prueba»:** poner los textos finales.

## Pruebas y validación en UAT

`RunSpecifiedTests` con estas 40 clases:

```
AseguradosControllerTest,AvisoMovimientoConcluidoTest,AvisoRenovacionPolizaTest,AvisoSolicitudSitioTest,BienVigenciaTest,BienvenidaPolizaTest,CensoColectivoControllerTest,CensoVehiculosControllerTest,ColectivoControllerTest,CorreoCotizacionAutoTest,CorreoOportunidadIATest,CorreosOportunidadTest,EliminarMovimientosTest,EnvioCorreoPlantillaTest,FlotillaControllerTest,JsonIaTest,MovimientosColectivoControllerTest,MovimientosFlotillaControllerTest,MovimientosUbicacionesControllerTest,OportunidadesPanelControllerTest,OpportunityComparisonPdfControllerTest,OpportunityControllerTest,OpportunityQuotesControllerTest,OtrasPolizasControllerTest,ParticipantesPolizaControllerTest,PdfOpportunityCreatorControllerTest,PolicyControllerTest,PolizaNumeroUnicoTest,PolizaVigenciasTest,PortalPolizasControllerTest,PortalPolizasMovimientosTest,PortalPolizasPestanasTest,PortalSitioControllerTest,ProductCoverageManagerControllerTest,ProductoPorSemejanzaTest,QuoteCreatorControllerTest,RenovacionGmmContributoriaTest,TriggerControlTest,VisualforcePdfRendererTest,PdfProcessorControllerTest
```

En PowerShell hay que pasarlas como lista (`$pruebas = "A,B,…".Split(",")` y luego `--tests $pruebas`). Si se mandan como un solo texto con comas, Salesforce no corre ninguna prueba.

**Validación en UAT el 27/11/2026, sin desplegar** (id `0AfcU00000CIKZFSA5`):
- **Resultado:** 725 componentes sin errores (el manifiesto con los campos y reglas de cada objeto). Pasan las 325 pruebas de las 40 clases. Cobertura de 91 %; la clase más baja es `PortalSitioController` con 81 %.
- **Manifiesto de esta corrida:** `manifest/validar-uat.xml`, que no lleva el proceso de ventas «Pólizas» ni el tipo de registro `Oportunidad_Colectiva`. Los dos usan valores que hay en PROD y no en UAT (etapa «Necesidad» y tipo «Existing Business»), y `Oportunidad_Colectiva` no existe en UAT. Esos dos se comprueban en la validación de PROD.
- **Qué no cubre esta corrida:** que el código funcione sin los triggers de Cobranza. UAT los tiene y PROD no los tendrá.

Con `RunLocalTests` no pasaría, por las 52 pruebas antiguas que ya fallan en UAT.

## Validación en PROD

Solo con autorización para tocar PROD, y después de crear la carpeta «Empresas» y las 2 etapas:

```
sf project deploy validate --manifest manifest/release-prod.xml --target-org <alias de PROD> --test-level RunSpecifiedTests --tests $pruebas
```
