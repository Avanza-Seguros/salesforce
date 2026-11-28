# Liberación a PROD: Sitio de Empresas e Insurance Policy, sin Cobranza ni Claims

- **Rama:** `release/prod-sitio-empresas`, hecha a partir de `Siniestros-en-Claims` en el commit `ae656d1`.
- **Manifiesto:** `manifest/release-prod.xml`, con 632 componentes y API 68.0.
- **Validado en PROD sin desplegar el 27/11/2026** (id `0AfUn000001S5KLKA0`): 729 componentes y 325 pruebas bien, con 90.3 % de cobertura.
- **Desplegado en PROD el 27/11/2026, de 20:07 a 20:10** (Quick Deploy `0AfUn000001S5LxKAK`): los 729 componentes, sin errores. Ver «Despliegue en PROD».
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
| Clases Apex | 83 (42 de prueba) | Reglas de validación | 14 |
| Componentes LWC | 36 | Flujos | 11 |
| Documentos (logos de correos) | 16 | Prompts de IA | 10 |
| Formatos de página | 15 | Vistas de lista | 10 |
| Objetos (los 5 nuevos, Póliza y Cobertura de producto) | 7 | Formatos compactos | 8 |
| Plantillas de correo (carpeta Empresas) | 7 | Conjuntos de permisos | 5 |
| Perfiles (solo lo nuevo) | 4 | Listas de valores (globales 3, estándar 4) | 7 |
| Otros (páginas VF, triggers, proceso de ventas, permisos, pestaña, páginas, menú, contenido del sitio, acciones, etc.) | 23 | **Total** | **632** |

Esto cubre:
- Pólizas empresariales: asegurados, vehículos y ubicaciones, movimientos, solicitudes, seguimiento y correos a asegurados.
- Crear Póliza y Crear Oportunidad, con el comparativo.
- Gestión comercial.
- Vigencias, renovación y avisos.
- El Sitio de Empresas: controladores, LWC, menú de navegación y el contenido del sitio (`ExperienceBundle` `Avanza_Empresas1`, recuperado de UAT sin la página «mis-pagos»).

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
| `Opportunity.Agente_Relacionado__c` | El filtro sigue opcional, como en PROD, aunque ya excluye «Descartado» e «Inactivo». Obligatorio da un error interno de Salesforce: hay 383 oportunidades ligadas a agentes así (374 «Inactivo» y 9 «Descartado»). Conserva el historial de cambios del campo, que la rama le quitaba |
| Página `Insurance_Policy_Record_Page` | Sin la pestaña Vigencias: su componente `policyTerms` es de Cobranza (lee las cuotas) |
| Formato de oportunidad | Sin la acción Enviar correo en la lista de pólizas, porque la acción no existía aún en PROD. Se volvió a poner después del despliegue, el 27/11/2026 |
| `BienvenidasPoliza`, `BienvenidaPolizaTest`, `PdfProcessorController` y `TriggerControlTest` | Se agregaron al manifiesto: cambiaron respecto a PROD y faltaban. Sin ellas corría la prueba vieja de PROD, que crea una oportunidad con Ramo «Auto», valor que los tipos de registro nuevos ya no aceptan |
| `CorreoOportunidadIATest` | La fecha de pago de prueba va a mediodía local; a medianoche GMT, en la zona horaria de México caía un día antes |
| `PortalPolizasPestanasTest` | Sube el documento de prueba solo con el sitio publicado; uno en construcción no tiene miembros y no acepta archivos |
| Contenido del sitio | Entró al paquete para que el menú encuentre sus páginas, sin la ruta ni la vista «mis-pagos» |

El LWC `portalPagos` va en el paquete porque compila, pero no se llega a él desde el sitio: el contenido del sitio va sin la página «mis-pagos».

## Decisiones aplicadas en esta rama

Se aplicaron las recomendaciones del plan; falta el visto bueno de Avanza.

1. **Listas rediseñadas en Gestión comercial: se conservan los valores de PROD y los tipos de registro solo muestran los nuevos.** Ningún registro de PROD se queda con un valor borrado.

   | Lista | Valores nuevos | Valores de PROD que se conservan | Total |
   |---|---|---|---|
   | Mercado de la oportunidad | 7 | 20 | 27 |
   | Plan producto | 1 | 126 | 127 |
   | Categoría GMM, Vida, Dentegra y Adicional del contacto | 9, 6, 3 y 3 | «06» en cada una | 10, 7, 4 y 4 |
   | Ramo de la oportunidad (lista propia del campo, con los mismos valores que la lista global de UAT) | 12 | 9 que tenía el campo Ramo de PROD («Gastos medicos», «Auto», «Accidentes», «Ahorro», «Retiro», «Mascota», «Transportes», «Administrativa», «Flotilla») | 21 |

   - **Tipos de registro de oportunidad:**
     - Colectiva, que solo existe en PROD, ahora muestra los valores nuevos de Ramo, Mercado y Plan producto, porque el código crea oportunidades con esos valores y las listas son restringidas.
     - En Individual y Oportunidades, Tipo muestra los valores de PROD («Existing Business» y «New Business»), no los de UAT.
   - **Familia de producto:** en PROD solo tiene «None» y ningún producto lo usa (los 110 están vacíos). El archivo se queda con los 11 valores nuevos.
2. **Etapas de la oportunidad: se conservan las de PROD y se agregan las 2 nuevas.** El proceso de ventas «Pólizas» lleva «Necesidad», «Propuesta», «Cierre», «Emitido», «Póliza», «Closed Won» y «Closed Lost», más «Gestion Comercial» y «En proceso de emision». Esas dos ya se crearon en PROD el 27/11/2026.
3. **Las 6 reglas de validación van apagadas,** como en UAT, donde se probó todo. Activarlas es otro cambio con su propia prueba.

## Riesgos que solo se ven en PROD

- **Ramo de la oportunidad queda con lista propia en PROD** y en UAT y DEV usa la lista global «Ramo». Un despliegue futuro desde develop que lleve `Opportunity.Ramo__c` va a fallar en PROD por lo mismo; ese campo hay que dejarlo fuera o igualar UAT y DEV a PROD.
- **Flujos de oportunidad que solo están activos en PROD:** `Flujo_Oportunidades_Avanza`, `Poliza_de_oportunidad`, `Oportunidad_Telefono` y `Prospecto_Oportunidad` crean pólizas de `Polizas__c` y reescriben datos de la oportunidad; en UAT están apagados. Las 325 pruebas pasaron con ellos activos, pero conviene revisarlos en el ensayo.
- **Tipo de oportunidad:** el código pone `New_Business` cuando el formulario no trae Tipo. En PROD ese valor no existe; como Tipo no es una lista restringida, se guarda igual, pero aparecerá como valor inactivo.

## Fuera del paquete

- **Carpeta de plantillas «Empresas»:** ya existe en PROD.
- **Etapas nuevas de la oportunidad:** «Gestion Comercial» y «En proceso de emision» (punto 2); ya creadas en PROD.
- **El sitio Avanza Empresas** (ya creado en PROD el 27/11/2026, sin publicar; su contenido va en el paquete):
  - Miembros, usuario invitado y publicarlo.
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
- **Manifiesto de esta corrida:** `manifest/validar-uat.xml`. No lleva el proceso de ventas «Pólizas» ni los tipos de registro `Oportunidad_Colectiva`, `Oportunidad_Individual` y `Oportunidades`, porque usan valores que hay en PROD y no en UAT: la etapa «Necesidad» y el tipo «Existing Business». Además, `Oportunidad_Colectiva` no existe en UAT. Esos cuatro se comprueban en la validación de PROD. Tampoco lleva `Opportunity.Ramo__c`, que en UAT usa la lista global y no se puede cambiar a lista propia, ni el contenido del sitio, que en UAT sí tiene la página «mis-pagos».
- **Qué no cubre esta corrida:** que el código funcione sin los triggers de Cobranza. UAT los tiene y PROD no los tendrá.

Con `RunLocalTests` no pasaría, por las 52 pruebas antiguas que ya fallan en UAT.

## Validación en PROD

Solo con autorización para tocar PROD:

```
sf project deploy validate --manifest manifest/release-prod.xml --target-org AvanzaPRD --test-level RunSpecifiedTests --tests $pruebas
```

**Primera validación, 27/11/2026, sin desplegar** (id `0AfUn000001S4rJKAS`): no pasó. Hubo 72 errores en 740 componentes, y por eso no corrió ninguna prueba. Lo que no necesitaba decisión ya se corrigió en la rama (ver «Ajustes hechos en esta rama»). Lo demás se resolvió el mismo 27/11/2026, con autorización:

| Error | Qué había en PROD | Qué se hizo |
|---|---|---|
| `Product2.Aseguradora__c` no puede pasar a búsqueda | Lista de selección con 16 valores. 2 productos tenían «GNP» y los otros 108 estaban vacíos. Solo la usaba el formato de producto | Se borró el campo en PROD (despliegue `0AfUn000001S4xlKAC`). Quedó en los campos borrados como `Aseguradora_del` y el nombre quedó libre: una prueba sin guardar confirmó que la búsqueda de la rama se puede crear, así que no hizo falta borrarlo para siempre. Respaldo en `C:\Salesforce\Avanza\respaldos-prod\2026-11-27-aseguradora-producto`. **Después del despliegue:** crear la aseguradora GNP, que en PROD no existe (solo hay SMNYL e INSIGNIA LIFE), y asignársela a «Capitaliza» y «Profesional» |
| `Opportunity.Ramo__c` no puede pasar a la lista global | Lista propia del campo con 15 valores. PROD no ofrece «Promover a conjunto de valores global» para ese campo | En la rama, `Ramo__c` conserva su lista propia con los 21 valores que tiene la lista global en UAT, que incluyen los 15 de PROD. La lista global `Ramo` salió del paquete porque ningún otro campo la usa |
| Proceso de ventas «Pólizas»: no existe «En proceso de emision» | No estaban las 2 etapas nuevas | Se crearon en PROD (despliegue `0AfUn000001S4uXKAS`): «Gestion Comercial» (40 %) después de «Propuesta» y «En proceso de emision» (75 %) después de «Emitido», abiertas y en Canalización, como en UAT. Las 6 etapas inactivas siguen igual |
| Menú `SFDC_Default_Navigation_Avanza_Empresas`: no existe el sitio | No existía el sitio «Avanza Empresas» | Se creó en PROD con la plantilla Customer Service y el prefijo `empresas`, como en UAT. Está en construcción, sin publicar y sin contenido |
| `Opportunity.Agente_Relacionado__c`: error interno de Salesforce | El filtro es opcional y solo excluye «Descartado». La rama lo hace obligatorio y excluye también «Inactivo», que sí existe en PROD | Se repitió; el filtro queda opcional (ver «Ajustes hechos en esta rama») |

Una prueba sin guardar en PROD de los campos de la oportunidad, sus 3 tipos de registro, el proceso de ventas «Pólizas» y el formato compacto `Financial_Opportunities` pasó con los 29 componentes.

**Siguientes validaciones, el mismo 27/11/2026:**

| Id | Resultado | Qué se corrigió después |
|---|---|---|
| `0AfUn000001S55pKAC` | 4 errores en 724 componentes; no corrieron pruebas | El filtro del agente, la pestaña Vigencias de Cobranza, la acción de correo del formato de oportunidad y el contenido del sitio, que el menú necesita |
| `0AfUn000001S5CHKA0` | 725 componentes bien; 319 de 323 pruebas | La zona horaria de `CorreoOportunidadIATest` y el documento de `PortalPolizasPestanasTest` |
| `0AfUn000001S5DtKAK`, `0AfUn000001S5FVKA0` y `0AfUn000001S5H7KAK` | 321 de 323 pruebas | Fallaba `BienvenidaPolizaTest`, que no estaba en el manifiesto, así que corría su versión vieja de PROD. Se agregaron esa clase, `BienvenidasPoliza`, `PdfProcessorController` y `TriggerControlTest`. En la primera de las tres hubo un registro de depuración temporal en PROD, ya borrado (las pruebas de un despliegue no generan log) |
| **`0AfUn000001S5KLKA0`** | **Pasó: 729 componentes, 325 pruebas bien y 90.3 % de cobertura.** Las clases más bajas tienen 81 % (`PortalSitioController` y `PdfProcessorController`) | Nada. Este id sirve para el Quick Deploy durante 10 días |

Los otros errores vienen de esos:
- **De `Aseguradora__c`:** 42 clases no compilan porque usan `Aseguradora__r`. De ahí fallan los LWC, la página de la póliza, el flujo de solicitudes, los perfiles y conjuntos de permisos, el filtro de `Quote.Product__c` y, probablemente, la acción de correo en el formato de oportunidad.
- **De `Ramo__c`:** los tipos de registro `Oportunidad_Individual` y `Oportunidades` no encuentran «Mascotas».

## Despliegue en PROD

**Quick Deploy el 27/11/2026, de 20:07 a 20:10** (id `0AfUn000001S5LxKAK`, con la validación `0AfUn000001S5KLKA0`): los 729 componentes, sin errores. Lo pidió el usuario sabiendo que seguían pendientes el visto bueno de Avanza a las decisiones, el ensayo en un sandbox copiado de PROD y las plantillas finales.

- **Respaldo para la reversa:** antes del despliegue se recuperó de PROD la versión anterior de todo lo del manifiesto, en `C:\Salesforce\Avanza\respaldos-prod\2026-11-27-antes-del-quick-deploy`. Tiene los 154 componentes que ya existían; los demás eran nuevos.
- **Revisión en PROD después del despliegue:** están las clases del sitio y de pólizas, los 5 objetos nuevos y los triggers `BienPolizaVigenciaTrigger` y `PolizaReglasTrigger`, activos. Las 6 reglas quedaron apagadas y el menú del sitio quedó en la red «Avanza Empresas», que sigue en construcción.
- **Campos sin acceso:** de los 198 campos nuevos, 195 quedaron sin lectura para el perfil Administrador, porque el perfil del paquete solo llevaba lo nuevo. Se agregó el conjunto de permisos `Polizas_Sitio_Empresas_Campos` («Pólizas y Sitio de Empresas: campos nuevos», despliegue `0AfUn000001S5PBKA0`). Da lectura en 194 campos y edición en 190; los 4 restantes son fórmulas. Deja fuera 4 campos obligatorios, que no admiten permiso. Además da crear, leer, editar y borrar en los 5 objetos nuevos. Está asignado a los 2 administradores activos (Abraham Gonzalez y Administrador Avanza); falta asignarlo a los demás usuarios internos que operen pólizas y cotizaciones. Su archivo está en `force-app/main/default/permissionsets/` y no está en `release-prod.xml`, porque se desplegó aparte.

**Pendiente en PROD:**
1. ~~Crear la aseguradora GNP y asignársela a «Capitaliza» y «Profesional».~~ Hecho el 27/11/2026: GNP es `a0uUn00000CrAC1IAN` y ya está en los 2 productos.
2. ~~Volver a poner la acción Enviar correo en la lista de pólizas del formato de oportunidad.~~ Hecho el 27/11/2026 (despliegue `0AfUn000001S5SPKA0`); el formato de la rama ya la trae otra vez.
3. Asignar los conjuntos de permisos (hoy sin asignar): a los internos, `Polizas_Sitio_Empresas_Campos`, `Portal_Polizas_Vista_Previa`, `Censo_Colectivo`, `Vehiculos_FSC` y `Logos_Correos`; a los usuarios del sitio, `Portal_Polizas_Cliente`.
4. Sitio «Avanza Empresas»: miembros, usuario invitado, licencias y publicarlo.
5. Plantillas de alta, baja y cambio: siguen como «Prueba V1»; un movimiento real las mandaría a asegurados.
6. Decidir si se programa el aviso de renovación.
7. Visto bueno de Avanza a las decisiones de listas, etapas y reglas, que ya están en PROD.
