/**
 *   @name: InsuredSubjectBackfillBatch
 *   @version: 1.0
 *   @creation date: 08/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Rellena el campo «Asegurado o bien» de las pólizas que ya existían antes
 *                 de que se mantuviera solo, y de las que se cargaron con los triggers
 *                 apagados. Se puede volver a correr: solo guarda las pólizas cuyo texto cambia.
 *                 Uso: Database.executeBatch(new InsuredSubjectBackfillBatch(), 200);
 */
public with sharing class InsuredSubjectBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
	public Integer updated = 0;

	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocator(
			[SELECT Id FROM InsurancePolicy ORDER BY Id]
		);
	}

	public void execute(
		Database.BatchableContext context,
		List<InsurancePolicy> scope
	) {
		updated += InsuredSubjectService.recalculate(
			new Map<Id, InsurancePolicy>(scope).keySet()
		);
	}

	public void finish(Database.BatchableContext context) {
		CobranzaLog.info(
			CobranzaLog.STAGE_DATOS_POLIZA,
			CobranzaLog.EVENT_INSURED_SUBJECT_BACKFILLED,
			'Relleno del campo Asegurado o bien terminado: ' +
				updated +
				' polizas actualizadas.'
		);
		AppLogger.flush();
	}
}
