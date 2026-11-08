import { buildRows, isFleet } from "../installmentRows";

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

	it("la emisión original no se marca como endoso, venga en '0' o en '000000'", () => {
		const corta = cuota({
			Id: "e1",
			carrierReceiptNumber__c: "0000010001",
			carrierEndorsementNumber__c: "0",
			carrierInstallmentNumber__c: 1
		});
		const larga = cuota({
			Id: "e2",
			sequenceNumber__c: 2,
			carrierReceiptNumber__c: "0000010002",
			carrierEndorsementNumber__c: "000000",
			carrierInstallmentNumber__c: 2
		});

		const { rows } = buildRows([corta, larga]);

		expect(rows.map((r) => r.sequenceLabel)).toEqual(["Cuota 1", "Cuota 2"]);
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

	it("una cuota estimada se marca, dice que no tiene recibo y muestra su mora", () => {
		const estimada = cuota({
			Id: "g1",
			isEstimated__c: true,
			expectedAmount__c: 2806.55,
			outstandingAmount__c: 2806.55,
			installmentStatus__c: "Vencido",
			daysOverdue__c: 181
		});
		const real = cuota({ Id: "g2", carrierReceiptNumber__c: "000101" });

		const { rows, totals } = buildRows([estimada, real]);

		expect(rows[0].sequenceLabel).toBe("Cuota 1 · Estimada");
		expect(rows[0].receiptLabel).toBe("Sin recibo aún");
		expect(rows[0].daysOverdue).toBe(181);
		expect(rows[1].sequenceLabel).toBe("Cuota 1");
		expect(rows[1].receiptLabel).toBe("000101");
		expect(totals.estimated).toBe(2806.55);
		expect(totals.expected).toBe(2906.55);
	});

	it("si un recibo no trae número de la aseguradora, todas se numeran con la secuencia del plan", () => {
		// Afirme: el primer recibo llega sin serie y el segundo como "1/1"; los dos decían "Cuota 1".
		const sinSerie = cuota({ Id: "h1", carrierReceiptNumber__c: "21786960" });
		const conSerie = cuota({
			Id: "h2",
			sequenceNumber__c: 2,
			carrierReceiptNumber__c: "22941868",
			carrierInstallmentNumber__c: 1
		});

		const { rows } = buildRows([sinSerie, conSerie]);

		expect(rows.map((r) => r.sequenceLabel)).toEqual(["Cuota 1", "Cuota 2"]);
	});

	it("si la aseguradora repite el número en documentos distintos, se numera con la secuencia del plan", () => {
		// HDI: dos recibos "1/1" sin endoso que los distinga.
		const primero = cuota({ Id: "i1", carrierInstallmentNumber__c: 1 });
		const segundo = cuota({
			Id: "i2",
			sequenceNumber__c: 2,
			carrierInstallmentNumber__c: 1
		});
		// Un endoso conserva su indicación aunque se numere con la secuencia.
		const endoso = cuota({
			Id: "i3",
			sequenceNumber__c: 3,
			carrierInstallmentNumber__c: 1,
			carrierEndorsementNumber__c: "196001080"
		});

		const { rows } = buildRows([primero, segundo, endoso]);

		expect(rows.map((r) => r.sequenceLabel)).toEqual([
			"Cuota 1",
			"Cuota 2",
			"Cuota 3 · Endoso 196001080"
		]);
	});

	it("las estimadas siguen la secuencia del plan detrás de la cuota con recibo", () => {
		const conRecibo = cuota({
			Id: "j1",
			carrierReceiptNumber__c: "D-33799046",
			carrierInstallmentNumber__c: 1
		});
		const estimada = cuota({
			Id: "j2",
			sequenceNumber__c: 2,
			isEstimated__c: true
		});

		const { rows } = buildRows([conRecibo, estimada]);

		expect(rows.map((r) => r.sequenceLabel)).toEqual([
			"Cuota 1",
			"Cuota 2 · Estimada"
		]);
	});

	it("cada fila lleva el periodo de su recibo, también los reemplazados", () => {
		const cancelado = cuota({
			Id: "k1",
			installmentStatus__c: "Cancelado",
			periodStartDate__c: "2026-06-19",
			periodEndDate__c: "2026-06-19"
		});
		const vivo = cuota({
			Id: "k2",
			replacesInstallment__c: "k1",
			periodStartDate__c: "2026-06-19",
			periodEndDate__c: "2026-09-19"
		});

		const { rows } = buildRows([cancelado, vivo]);

		expect(rows[0].periodStartDate__c).toBe("2026-06-19");
		expect(rows[0].periodEndDate__c).toBe("2026-09-19");
		expect(rows[0]._children[0].periodEndDate__c).toBe("2026-06-19");
	});

	it("el periodo del recibo va en una sola columna y dice qué extremo falta", () => {
		const { rows } = buildRows([
			cuota({
				Id: "p1",
				periodStartDate__c: "2025-12-16",
				periodEndDate__c: "2026-12-16"
			}),
			cuota({
				Id: "p2",
				sequenceNumber__c: 2,
				periodStartDate__c: "2026-01-01"
			}),
			cuota({ Id: "p3", sequenceNumber__c: 3, periodEndDate__c: "2026-02-01" }),
			cuota({ Id: "p4", sequenceNumber__c: 4 })
		]);
		const byId = Object.fromEntries(rows.map((r) => [r.Id, r.coveragePeriod]));

		// Las fechas no se corren un día por la zona horaria del usuario.
		expect(byId.p1).toMatch(/16.*2025 – .*16.*2026/);
		expect(byId.p2).toMatch(/^Desde .*1.*2026$/);
		expect(byId.p3).toMatch(/^Hasta .*1.*2026$/);
		expect(byId.p4).toBeNull();
	});

	it("una estimada cancelada no se muestra ni cuenta", () => {
		const real = cuota({ Id: "l1", carrierReceiptNumber__c: "80009593552" });
		const estimadaCancelada = cuota({
			Id: "l2",
			isEstimated__c: true,
			installmentStatus__c: "Cancelado"
		});

		const { rows, totals } = buildRows([real, estimadaCancelada]);

		expect(rows.map((r) => r.Id)).toEqual(["l1"]);
		expect(totals.count).toBe(1);
	});

	it("sin cuotas no falla", () => {
		expect(buildRows(null)).toEqual({
			rows: [],
			totals: {
				expected: 0,
				matched: 0,
				outstanding: 0,
				estimated: 0,
				count: 0
			},
			fleet: false
		});
	});

	describe("flotilla o colectiva", () => {
		const policy = {
			Status: "Vigente",
			ExpirationDate: "2026-12-16T06:00:00.000Z"
		};
		const bien = (id, overrides) => ({
			Id: id,
			AssetName: "Local",
			IsActive: true,
			EffectiveToDate: "2026-12-16",
			...overrides
		});
		const recibo = (id, due, asset, overrides) =>
			cuota({
				Id: id,
				dueDate__c: due,
				carrierReceiptNumber__c: `R-${id}`,
				policyAsset__c: asset.Id,
				policyAsset__r: asset,
				paymentPlan__r: { Name: "PP-001", insurancePolicy__r: policy },
				...overrides
			});

		const versa = bien("ipa1", {
			AssetCode: "002",
			AssetName: "NISSAN VERSA 2024",
			CustomerProperty: { Vin: "3N1CN8AE0RL000001" }
		});
		const local = bien("ipa2", { AssetName: "Inciso 1 - Av. Vallarta 1340" });
		const baja = bien("ipa3", {
			AssetCode: "3",
			AssetName: "KIA RIO",
			IsActive: false,
			EffectiveToDate: "2026-03-01"
		});
		const records = [
			recibo("f1", "2025-12-16", versa, {
				installmentStatus__c: "Conciliado",
				matchedAmount__c: 100,
				outstandingAmount__c: 0
			}),
			recibo("f2", "2025-12-16", baja, { installmentStatus__c: "Cancelado" }),
			recibo("f3", "2025-12-16", local),
			recibo("f4", "2026-01-16", versa)
		];

		it("una póliza sin recibos por inciso no es flotilla", () => {
			expect(isFleet([cuota({ Id: "x1" })])).toBe(false);
			expect(isFleet(records)).toBe(true);
		});

		it("agrupa por fecha con el resumen y ordena los incisos, las bajas al final y en gris", () => {
			const { rows, totals, fleet } = buildRows(records);

			expect(fleet).toBe(true);
			expect(rows.map((r) => r.Id)).toEqual([
				"fecha-2025-12-16",
				"fecha-2026-01-16"
			]);
			expect(rows[0].sequenceLabel).toMatch(
				/16.*2025 · 3 incisos · 1 pagado · 1 pendiente · 1 cancelado$/
			);
			const hijos = rows[0]._children;
			expect(hijos.map((h) => h.Id)).toEqual(["f3", "f1", "f2"]);
			expect(hijos[0].sequenceLabel).toBe("Inciso 1");
			expect(hijos[0].subjectLabel).toBe("Av. Vallarta 1340");
			expect(hijos[0].subjectUrl).toBe("/ipa2");
			expect(hijos[1].subjectLabel).toBe(
				"NISSAN VERSA 2024 · serie 3N1CN8AE0RL000001"
			);
			expect(hijos[2].sequenceLabel).toMatch(/^Inciso 3 · Baja .*2026$/);
			expect(hijos[2].statusClass).toBe("slds-text-color_weak");
			expect(hijos[2].subjectClass).toBe("slds-text-color_weak");
			// Los totales son los de siempre: cuentan las cuotas vivas, sin las canceladas.
			expect(totals).toEqual({
				expected: 300,
				matched: 100,
				outstanding: 200,
				estimated: 0,
				count: 4
			});
		});

		it("agrupa por inciso con sus recibos por fecha", () => {
			const { rows, totals } = buildRows(records, "inciso");

			expect(rows.map((r) => r.sequenceLabel.split(" · ")[0])).toEqual([
				"Inciso 1",
				"Inciso 2",
				"Inciso 3"
			]);
			expect(rows[1].sequenceLabel).toMatch(/· 2 recibos ·/);
			expect(rows[1]._children.map((h) => h.Id)).toEqual(["f1", "f4"]);
			expect(rows[1]._children[1].sequenceLabel).toMatch(/16.*2026/);
			expect(rows[2].statusClass).toBe("slds-text-color_weak");
			expect(totals.expected).toBe(300);
		});

		it("una póliza vencida no pone de baja a sus incisos apagados", () => {
			const vencida = {
				Status: "Vencido",
				ExpirationDate: "2026-12-16T06:00:00.000Z"
			};
			const apagado = bien("ipa9", { AssetCode: "9", IsActive: false });
			const { rows } = buildRows([
				recibo("v1", "2025-12-16", apagado, {
					paymentPlan__r: { Name: "PP", insurancePolicy__r: vencida }
				})
			]);

			expect(rows[0]._children[0].sequenceLabel).toBe("Inciso 9");
		});

		it("un certificado dice el nombre de la persona y los reemplazados siguen colgando de él", () => {
			const persona = {
				ParticipantCode: "1234",
				ParticipantName: "Ana López",
				IsActiveParticipant: true
			};
			const deLaPersona = (id, overrides) =>
				cuota({
					Id: id,
					policyParticipant__c: "ipp1",
					policyParticipant__r: persona,
					paymentPlan__r: { Name: "PP", insurancePolicy__r: policy },
					...overrides
				});
			const { rows } = buildRows([
				deLaPersona("c1", { installmentStatus__c: "Cancelado" }),
				deLaPersona("c2", { replacesInstallment__c: "c1" }),
				cuota({ Id: "c3", sequenceNumber__c: 2 })
			]);

			const hijos = rows[0]._children;
			expect(hijos[0].sequenceLabel).toBe("Certificado 1234");
			expect(hijos[0].subjectLabel).toBe("Ana López");
			expect(hijos[0]._children.map((h) => h.Id)).toEqual(["c1"]);
			expect(hijos[1].sequenceLabel).toBe("Sin inciso");
		});
	});
});
