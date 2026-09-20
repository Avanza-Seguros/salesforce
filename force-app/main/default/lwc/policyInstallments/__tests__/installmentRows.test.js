import { buildRows } from "../installmentRows";

/** Cuota como la devuelve el controlador, con lo mínimo que usa la pestaña. */
function cuota(overrides) {
	return {
		Id: overrides.Id,
		Name: overrides.Id,
		sequenceNumber__c: 1,
		dueDate__c: "2026-05-08",
		expectedAmount__c: 100,
		matchedAmount__c: 0,
		outstandingAmount__c: 100,
		installmentStatus__c: "Pendiente",
		daysOverdue__c: 0,
		carrierReceiptNumber__c: null,
		carrierEndorsementNumber__c: null,
		carrierInstallmentNumber__c: null,
		replacesInstallment__c: null,
		paymentPlan__r: { Name: "PP-001" },
		...overrides
	};
}

describe("buildRows", () => {
	it("deja una fila por cuota y cuelga de ella los recibos reemplazados", () => {
		// La aseguradora canceló el recibo original y emitió otro para el mismo periodo.
		const original = cuota({
			Id: "a1",
			carrierReceiptNumber__c: "0298295215",
			carrierEndorsementNumber__c: "000000",
			carrierInstallmentNumber__c: 2,
			installmentStatus__c: "Cancelado"
		});
		const reemitida = cuota({
			Id: "a2",
			sequenceNumber__c: 2,
			carrierReceiptNumber__c: "0306187271",
			carrierEndorsementNumber__c: "135906",
			carrierInstallmentNumber__c: 2,
			replacesInstallment__c: "a1"
		});

		const { rows, totals } = buildRows([original, reemitida]);

		expect(rows).toHaveLength(1);
		expect(rows[0].Id).toBe("a2");
		expect(rows[0].sequenceLabel).toBe("Cuota 2");
		expect(rows[0].replacedLabel).toBe("1 recibo reemplazado");
		expect(rows[0]._children).toHaveLength(1);
		expect(rows[0]._children[0].sequenceLabel).toBe("Recibo 0298295215");
		expect(totals.count).toBe(1);
		expect(totals.expected).toBe(100);
	});

	it("encadena varias reexpediciones y numera con la cuota de la emisión", () => {
		const emision = cuota({
			Id: "b1",
			carrierReceiptNumber__c: "0282678546",
			carrierEndorsementNumber__c: "000000",
			carrierInstallmentNumber__c: 2,
			installmentStatus__c: "Cancelado"
		});
		const primera = cuota({
			Id: "b2",
			carrierReceiptNumber__c: "0285762815",
			carrierEndorsementNumber__c: "163097",
			carrierInstallmentNumber__c: 2,
			installmentStatus__c: "Cancelado",
			replacesInstallment__c: "b1"
		});
		const vigente = cuota({
			Id: "b3",
			carrierReceiptNumber__c: "0293199602",
			carrierEndorsementNumber__c: "176238",
			// La serie reexpedida vuelve a empezar en 1: no es la cuota 1 de la póliza.
			carrierInstallmentNumber__c: 1,
			installmentStatus__c: "Conciliado",
			matchedAmount__c: 100,
			outstandingAmount__c: 0,
			replacesInstallment__c: "b2"
		});

		const { rows, totals } = buildRows([emision, primera, vigente]);

		expect(rows).toHaveLength(1);
		expect(rows[0].Id).toBe("b3");
		expect(rows[0].sequenceLabel).toBe("Cuota 2");
		expect(rows[0].replacedLabel).toBe("2 recibos reemplazados");
		expect(rows[0]._children.map((c) => c.Id)).toEqual(["b2", "b1"]);
		expect(totals.matched).toBe(100);
		expect(totals.outstanding).toBe(0);
	});

	it("una cuota de un endoso lo indica en su etiqueta", () => {
		const aumento = cuota({
			Id: "c1",
			carrierReceiptNumber__c: "0284889399",
			carrierEndorsementNumber__c: "142063",
			carrierInstallmentNumber__c: 2
		});

		const { rows } = buildRows([aumento]);

		expect(rows[0].sequenceLabel).toBe("Cuota 2 · Endoso 142063");
		expect(rows[0]._children).toBeUndefined();
	});

	it("lo que ya no se debe no suma en los totales", () => {
		const pagada = cuota({
			Id: "d1",
			installmentStatus__c: "Conciliado",
			matchedAmount__c: 100,
			outstandingAmount__c: 0
		});
		const cancelada = cuota({ Id: "d2", installmentStatus__c: "Cancelado" });
		const condonada = cuota({ Id: "d3", installmentStatus__c: "Condonado" });
		const pendiente = cuota({ Id: "d4", installmentStatus__c: "Vencido" });

		const { rows, totals } = buildRows([
			pagada,
			cancelada,
			condonada,
			pendiente
		]);

		expect(rows).toHaveLength(4);
		expect(totals.expected).toBe(200);
		expect(totals.outstanding).toBe(100);
		expect(rows[1].statusClass).toBe("slds-text-color_weak");
		expect(rows[3].statusClass).toBe("slds-text-color_error");
	});

	it("una cuota sin datos de la aseguradora se numera como siempre", () => {
		const sinAseguradora = cuota({ Id: "e1", sequenceNumber__c: 3 });

		const { rows } = buildRows([sinAseguradora]);

		expect(rows[0].sequenceLabel).toBe("Cuota 3");
	});

	it("los días de mora solo se muestran cuando los hay", () => {
		const alCorriente = cuota({ Id: "f1", daysOverdue__c: 0 });
		const enMora = cuota({
			Id: "f2",
			daysOverdue__c: 12,
			installmentStatus__c: "Vencido"
		});

		const { rows } = buildRows([alCorriente, enMora]);

		expect(rows[0].daysOverdue).toBeNull();
		expect(rows[1].daysOverdue).toBe(12);
		expect(rows[1].overdueClass).toBe("slds-text-color_error");
	});

	it("sin cuotas no falla", () => {
		expect(buildRows(null)).toEqual({
			rows: [],
			totals: { expected: 0, matched: 0, outstanding: 0, count: 0 }
		});
	});
});
