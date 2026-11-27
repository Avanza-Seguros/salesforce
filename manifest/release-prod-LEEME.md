# Liberación a PROD: Sitio de Empresas e Insurance Policy, sin Cobranza ni Claims

- **Rama:** `release/prod-sitio-empresas`, hecha a partir de `Siniestros-en-Claims` en el commit `ae656d1`.
- **Manifiesto:** `manifest/release-prod.xml`, con 628 componentes y API 68.0.
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
| Formatos de página | 15 | Vistas de lista | 10 |
| Objetos (los 5 nuevos, Póliza y Cobertura de producto) | 7 | Formatos compactos | 8 |
| Plantillas de correo (carpeta Empresas) | 7 | Conjuntos de permisos | 5 |
| Perfiles (solo lo nuevo) | 4 | Listas de valores (globales 4, estándar 4) | 8 |
| Otros (páginas VF, triggers, proceso de ventas, permisos, pestaña, páginas, menú, acciones, etc.) | 22 | **Total** | **628** |

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
| Esos mismos tipos de registro | En las listas rediseñadas solo muestran los valores nuevos (ver «Decisiones aplicadas») |
| Tipo de registro `Insurance_Policy_Asset` | Sin el formato compacto `Insurance_Policy_Asset`, que no existe |
| Formato de Cuenta persona | Sin el botón `ScheduleAppointment`, que no existe |
| Reglas `Business_Account`, `Person_Account` y `Phone_Format` (Cuenta), y `Bloqueo_quotes_si_existe_aceptada`, `No_change_status` y `No_permite_aceptado` (Cotización) | Inactivas, como en UAT, donde se probó todo; en el repositorio venían activas |
| Manifiesto | API 68.0: el flujo `Set_PriceBook` está guardado en 68.0 |

Esto lo encontró la validación en PROD del 27/11/2026.

| Pieza | Ajuste |
|---|---|
| Tipos de registro de cuenta (`Business_Account`, `Default_Account`, `Person_Account` y `PersonAccount`) | Sin el Tipo «Financial» y sin las listas Ownership y Rating, que no existen en PROD |
| Tipo de registro `Contact` | Sin las listas GenderIdentity, Pronouns y LeadSource, que no existen en PROD |
| Tipo de registro `Oportunidad_Colectiva` | Sin «Platica Luxoft» ni «Siniestro Luxoft» en Mercado, que en PROD están inactivos |
| Formato `AccountFinancialSummary` y relación `Relaciones_del_cliente` | Fuera del paquete: sus objetos (Resumen financiero de cuenta y Relación entre cuentas) no están activados en PROD |

El LWC `portalPagos` va en el paquete porque compila, pero no se llega a él desde el sitio. No hay que crear la página «mis-pagos» en el sitio de PROD.

## Decisiones aplicadas en esta rama

Se aplicaron las recomendaciones del plan; falta el visto bueno de Avanza.

1. **Listas rediseñadas en Gestión comercial: se conservan los valores de PROD y los tipos de registro solo muestran los nuevos.** Ningún registro de PROD se queda con un valor borrado.

   | Lista | Valores nuevos | Valores de PROD que se conservan | Total |
   |---|---|---|---|
   | Mercado de la oportunidad | 7 | 20 | 27 |
   | Plan producto | 1 | 126 | 127 |
   | Categoría GMM, Vida, Dentegra y Adicional del contacto | 9, 6, 3 y 3 | «06» en cada una | 10, 7, 4 y 4 |
   | Ramo (lista global) | 12 | 9 que tenía el campo Ramo de PROD («Gastos medicos», «Auto», «Accidentes», «Ahorro», «Retiro», «Mascota», «Transportes», «Administrativa», «Flotilla») | 21 |

   - **Tipos de registro de oportunidad:**
     - Colectiva, que solo existe en PROD, ahora muestra los valores nuevos de Ramo, Mercado y Plan producto, porque el código crea oportunidades con esos valores y las listas son restringidas.
     - En Individual y Oportunidades, Tipo muestra los valores de PROD («Existing Business» y «New Business»), no los de UAT.
   - **Familia de producto:** en PROD solo tiene «None» y ningún producto lo usa (los 110 están vacíos). El archivo se queda con los 11 valores nuevos.
2. **Etapas de la oportunidad: se conservan las de PROD y se agregan las 2 nuevas.** El proceso de ventas «Pólizas» lleva «Necesidad», «Propuesta», «Cierre», «Emitido», «Póliza», «Closed Won» y «Closed Lost», más «Gestion Comercial» y «En proceso de emision». Esas dos hay que crearlas en PROD antes de validar.
3. **Las 6 reglas de validación van apagadas,** como en UAT, donde se probó todo. Activarlas es otro cambio con su propia prueba.

## Riesgos que solo se ven en PROD

- **Ramo de la oportunidad pasa a la lista global «Ramo».** La validación en PROD confirmó que no se puede por despliegue; hay que hacerlo a mano (ver «Validación en PROD»).
- **Tipo de oportunidad:** el código pone `New_Business` cuando el formulario no trae Tipo. En PROD ese valor no existe; como Tipo no es una lista restringida, se guarda igual, pero aparecerá como valor inactivo.

## Fuera del paquete

- **Carpeta de plantillas «Empresas»:** ya existe en PROD.
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

**Validación en UAT el 27/11/2026, sin desplegar y con las decisiones aplicadas** (id `0AfcU00000CILzxSAH`):
- **Resultado:** 723 componentes sin errores (el manifiesto con los campos y reglas de cada objeto). Pasan las 325 pruebas de las 40 clases. Cobertura de 91 %; la clase más baja es `PortalSitioController` con 81 %.
- **Manifiesto de esta corrida:** `manifest/validar-uat.xml`. No lleva el proceso de ventas «Pólizas» ni los tipos de registro `Oportunidad_Colectiva`, `Oportunidad_Individual` y `Oportunidades`, porque usan valores que hay en PROD y no en UAT: la etapa «Necesidad» y el tipo «Existing Business». Además, `Oportunidad_Colectiva` no existe en UAT. Esos cuatro se comprueban en la validación de PROD.
- **Qué no cubre esta corrida:** que el código funcione sin los triggers de Cobranza. UAT los tiene y PROD no los tendrá.

Con `RunLocalTests` no pasaría, por las 52 pruebas antiguas que ya fallan en UAT.

## Validación en PROD

Solo con autorización para tocar PROD:

```
sf project deploy validate --manifest manifest/release-prod.xml --target-org AvanzaPRD --test-level RunSpecifiedTests --tests $pruebas
```

**Primera validación, 27/11/2026, sin desplegar** (id `0AfUn000001S4rJKAS`): no pasó. Hubo 72 errores en 740 componentes, y por eso no corrió ninguna prueba. Lo que no necesitaba decisión ya se corrigió en la rama (ver «Ajustes hechos en esta rama»). Lo demás necesita un paso en PROD antes de volver a validar:

| Error | Qué hay en PROD | Paso antes de volver a validar |
|---|---|---|
| `Product2.Aseguradora__c` no puede pasar a búsqueda | Lista de selección con 16 valores. 2 productos tienen «GNP» y los otros 108 están vacíos. Solo la usa el formato de producto | Borrar el campo en PROD y quitarlo también de los campos borrados, para que el despliegue lo cree como búsqueda a Aseguradora. Después, poner la aseguradora GNP a esos 2 productos |
| `Opportunity.Ramo__c` no puede pasar a la lista global | Lista propia del campo con 15 valores; no hay ninguna lista global «Ramo» | En Configuración, «Promover a conjunto de valores global» con el nombre `Ramo`. El despliegue le agrega los valores nuevos |
| Proceso de ventas «Pólizas»: no existe «En proceso de emision» | No están las 2 etapas nuevas | Crear «Gestion Comercial» (40 %, Canalización, abierta) y «En proceso de emision» (75 %, Canalización, abierta), como en UAT |
| Menú `SFDC_Default_Navigation_Avanza_Empresas`: no existe el sitio | No existe el sitio «Avanza Empresas» | Crear el sitio antes de desplegar |
| `Opportunity.Agente_Relacionado__c`: error interno de Salesforce | El filtro es opcional y solo excluye «Descartado». La rama lo hace obligatorio y excluye también «Inactivo», que sí existe en PROD | Volver a validar; si se repite, dejar el filtro como está en PROD |

Los otros errores vienen de esos:
- **De `Aseguradora__c`:** 42 clases no compilan porque usan `Aseguradora__r`. De ahí fallan los LWC, la página de la póliza, el flujo de solicitudes, los perfiles y conjuntos de permisos, el filtro de `Quote.Product__c` y, probablemente, la acción de correo en el formato de oportunidad.
- **De `Ramo__c`:** los tipos de registro `Oportunidad_Individual` y `Oportunidades` no encuentran «Mascotas».
