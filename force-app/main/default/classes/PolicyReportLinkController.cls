/**
 * Abre el informe «Todas las pólizas» desde el botón de las vistas de lista de pólizas.
 * Se busca por nombre único porque el Id del informe cambia de una org a otra.
 */
public with sharing class PolicyReportLinkController {
	public static final String REPORT_NAME = 'Todas_las_polizas';

	public PolicyReportLinkController(
		ApexPages.StandardSetController controller
	) {
	}

	public PageReference openReport() {
		List<Report> reports = [
			SELECT Id
			FROM Report
			WHERE DeveloperName = :REPORT_NAME
			LIMIT 1
		];
		if (reports.isEmpty()) {
			ApexPages.addMessage(
				new ApexPages.Message(
					ApexPages.Severity.ERROR,
					'No se encontró el informe «Todas las pólizas».'
				)
			);
			return null;
		}
		return reportPage(reports[0].Id);
	}

	@TestVisible
	private static PageReference reportPage(Id reportId) {
		PageReference target = new PageReference(
			'/lightning/r/Report/' + reportId + '/view'
		);
		target.setRedirect(true);
		return target;
	}
}
