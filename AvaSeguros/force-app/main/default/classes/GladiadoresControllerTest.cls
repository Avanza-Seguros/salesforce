@isTest
public class GladiadoresControllerTest {
    @testSetup static void setup() {
        Gladiadores__c gld = new Gladiadores__c();
        gld.Name = 'test';
        gld.Contrase_a__c = 'test';
        gld.Tipo_de_Contrato__c = 'Colaborador';
        gld.Fecha_de_Alta__c = System.today();
        gld.sexo__c = 'Masculino';
        gld.email__c = 'Test@test.com';

        Insert gld;
        /*

        gld.Tipo_de_Contrato__c
        gld.Tipo_de_Contrato__c
        gld.Tipo_de_Contrato__c
        gld.Tipo_de_Contrato__c
        */
        Insert new Solicitudes_de_Vacaciones__c(
            Gladiador__c = gld.Id,
            Fecha_de_Solicitud__c = System.today(),
            Dias_Desde__c = date.valueOf(System.today()),
            Dias_Hasta__c = date.valueOf(System.today()),
            TIpo_de_Permiso__c = 'Vacaciones',
            Motivo_Ausencia__c = null,
            Motivo_de_ausencia__c = null,
            Dias_que_se_Solicitan__c = 1,
            Etapa__c = 'Creado'
        );
    }

    static testmethod void getAllGladiadoresTest(){
        GladiadoresController.getAllGladiadores();
    }

    static testmethod void getDiasEspecialesTest(){
        GladiadoresController.getDiasEspeciales();
    }

    static testmethod void getSolicitudesTest(){
        GladiadoresController.getSolicitudes([select Id from Gladiadores__c limit 1][0].Id);
    }

    static testmethod void getAuthenticateTest(){
        GladiadoresController.getAuthenticate([select Id from Gladiadores__c limit 1][0].Id, 'test');
    }

    static testmethod void createSolicitudVacacionesTest(){
        //(String fechaSolicitud, String idGladiadior, String fechaDesde, String fechaHasta, String tipoPermiso, String motivoAusencia, String motivoAusenciaDescription)
        GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today(), ''+System.today(), 'Vacaciones', '', '', '', '', '', '');
    }

    static testmethod void updateSolicitudVacacionesTest(){
        GladiadoresController.updateSolicitudVacaciones(
            ''+GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Vacaciones', '', '', '', '', '', '')[0].Id,
            ''+[select Id from Gladiadores__c limit 1][0].Id
        );
    }

    static testmethod void updateSolicitudVacacionesTest_3daysIssue(){
        try{
            GladiadoresController.updateSolicitudVacaciones(
                ''+GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today(), ''+System.today(), 'Vacaciones', '', '', '', '', '', '')[0].Id,
                ''+[select Id from Gladiadores__c limit 1][0].Id
            );
        }catch(Exception ex){
            System.debug('Catched exception');
        }
    }

    static testmethod void updateSolicitudVacacionesTest_daysInPastIssue(){
        
        Update new Gladiadores__c(
            Id = [select Id from Gladiadores__c limit 1][0].Id,
            Vacaciones_Otorgadas_2__c = 0
        );

        try{
            GladiadoresController.updateSolicitudVacaciones(
                ''+GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Vacaciones', '', '', '', '', '', '')[0].Id,
                ''+[select Id from Gladiadores__c limit 1][0].Id
            );
        }catch(Exception ex){
            System.debug('Catched exception');
        }
    } 

    static testmethod void deleteSolicitudVacacionesTest(){
            String IdDelete = ''+GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Vacaciones', '', '', '', '', '', '')[0].Id;
            GladiadoresController.deleteSolicitudVacaciones(
                IdDelete,
                ''+[select Id from Gladiadores__c limit 1][0].Id
            );
    }

    static testmethod void validateDiasEspecialesTest(){
        GladiadoresController.validateDiasEspeciales(
            [select Id,
                    Dias_Restantes__c,
                    Dias_Enfermedad__c, 
                    Dias_Fallecimiento__c, 
                    Dias_Familiar_Enfermedad__c, 
                    Dias_Hijo_Prematuro__c, 
                    Dias_Inexcusable__c, 
                    Dias_Lactancia__c, 
                    Dias_Matrimonio__c, 
                    Dias_Mudanza__c, 
                    Dias_Nacimiento__c,
                    Cita_medica__c,
                    Dias_Tomados__c 
                    from Gladiadores__c limit 1][0],
                    GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Permiso especial', 'Matrimonio', 'test', '', '', '', '')[0]
        );
        GladiadoresController.validateDiasEspeciales(
            [select Id,
                    Dias_Restantes__c,
                    Dias_Enfermedad__c, 
                    Dias_Fallecimiento__c, 
                    Dias_Familiar_Enfermedad__c, 
                    Dias_Hijo_Prematuro__c, 
                    Dias_Inexcusable__c, 
                    Dias_Lactancia__c, 
                    Dias_Matrimonio__c, 
                    Dias_Mudanza__c, 
                    Dias_Nacimiento__c,
                    Cita_medica__c,
                    Dias_Tomados__c 
                    from Gladiadores__c limit 1][0],
                    GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Permiso especial', 'Mudanza', 'test', '', '', '', '')[0]
        );
        GladiadoresController.validateDiasEspeciales(
            [select Id,
                    Dias_Restantes__c,
                    Dias_Enfermedad__c, 
                    Dias_Fallecimiento__c, 
                    Dias_Familiar_Enfermedad__c, 
                    Dias_Hijo_Prematuro__c, 
                    Dias_Inexcusable__c, 
                    Dias_Lactancia__c, 
                    Dias_Matrimonio__c, 
                    Dias_Mudanza__c, 
                    Dias_Nacimiento__c,
                    Cita_medica__c,
                    Dias_Tomados__c 
                    from Gladiadores__c limit 1][0],
                    GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Permiso especial', 'Nacimiento', 'test', '', '', '', '')[0]
        );
        GladiadoresController.validateDiasEspeciales(
            [select Id,
                    Dias_Restantes__c,
                    Dias_Enfermedad__c, 
                    Dias_Fallecimiento__c, 
                    Dias_Familiar_Enfermedad__c, 
                    Dias_Hijo_Prematuro__c, 
                    Dias_Inexcusable__c, 
                    Dias_Lactancia__c, 
                    Dias_Matrimonio__c, 
                    Dias_Mudanza__c, 
                    Dias_Nacimiento__c,
                    Cita_medica__c,
                    Dias_Tomados__c 
                    from Gladiadores__c limit 1][0],
                    GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Permiso especial', 'Fallecimiento', 'test', '', '', '', '')[0]
        );
        GladiadoresController.validateDiasEspeciales(
            [select Id,
                    Dias_Restantes__c,
                    Dias_Enfermedad__c, 
                    Dias_Fallecimiento__c, 
                    Dias_Familiar_Enfermedad__c, 
                    Dias_Hijo_Prematuro__c, 
                    Dias_Inexcusable__c, 
                    Dias_Lactancia__c, 
                    Dias_Matrimonio__c, 
                    Dias_Mudanza__c, 
                    Dias_Nacimiento__c,
                    Cita_medica__c,
                    Dias_Tomados__c 
                    from Gladiadores__c limit 1][0],
                    GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Permiso especial', 'Familiar enfermo', 'test', '', '', '', '')[0]
        );
        GladiadoresController.validateDiasEspeciales(
            [select Id,
                    Dias_Restantes__c,
                    Dias_Enfermedad__c, 
                    Dias_Fallecimiento__c, 
                    Dias_Familiar_Enfermedad__c, 
                    Dias_Hijo_Prematuro__c, 
                    Dias_Inexcusable__c, 
                    Dias_Lactancia__c, 
                    Dias_Matrimonio__c, 
                    Dias_Mudanza__c, 
                    Dias_Nacimiento__c,
                    Cita_medica__c,
                    Dias_Tomados__c 
                    from Gladiadores__c limit 1][0],
                    GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Permiso especial', 'Enfermedad', 'test', '', '', '', '')[0]
        );
    }

    static testmethod void UpdateFileTest(){
        String IdDelete = ''+GladiadoresController.createSolicitudVacaciones(''+System.today(), ''+[select Id from Gladiadores__c limit 1][0].Id, ''+System.today().addDays(10), ''+System.today().addDays(10), 'Vacaciones', '', '', '', '', '', '')[0].Id;
        ContentVersion testContentVersion = new ContentVersion();
        testContentVersion.Title = 'Test Document';
        testContentVersion.PathOnClient = 'TestPath/TestDocument.txt';
        testContentVersion.VersionData = Blob.valueOf('Test content');
        insert testContentVersion;
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id LIMIT 1][0].ContentDocumentId;
        GladiadoresController.UpdateFile(
            contentDocumentId,
            ''+[select Id from Gladiadores__c limit 1][0].Id
        );
    }

}