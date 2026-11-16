@IsTest
private class PolicyReportLinkControllerTest {
	@IsTest
	static void opensTheReportOrExplainsWhyNot() {
		PolicyReportLinkController controller = new PolicyReportLinkController(
			new ApexPages.StandardSetController(new List<InsurancePolicy>())
		);
		Test.setCurrentPage(Page.TodasLasPolizasInforme);

		PageReference target = controller.openReport();

		List<Report> reports = [
			SELECT Id
			FROM Report
			WHERE DeveloperName = :PolicyReportLinkController.REPORT_NAME
		];
		if (reports.isEmpty()) {
			Assert.isNull(target, 'Sin informe no hay a dónde ir');
			Assert.isTrue(
				ApexPages.hasMessages(ApexPages.Severity.ERROR),
				'Debe avisar de que falta el informe'
			);
		} else {
			Assert.areEqual(
				'/lightning/r/Report/' + reports[0].Id + '/view',
				target.getUrl()
			);
		}
	}

	@IsTest
	static void buildsTheLightningUrlOfTheReport() {
		Id fakeReportId = '00O000000000001AAA';

		PageReference target = PolicyReportLinkController.reportPage(fakeReportId);

		Assert.areEqual(
			'/lightning/r/Report/' + fakeReportId + '/view',
			target.getUrl()
		);
		Assert.isTrue(target.getRedirect(), 'Debe redirigir');
	}
}
