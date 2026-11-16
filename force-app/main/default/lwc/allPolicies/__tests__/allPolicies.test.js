import { createElement } from "lwc";
import AllPolicies from "c/allPolicies";
import { PAGE_SIZE, SEARCH_DELAY_MS } from "../policyRows";
import getPage from "@salesforce/apex/AllPoliciesController.getPage";
import getTotal from "@salesforce/apex/AllPoliciesController.getTotal";
import getFilterOptions from "@salesforce/apex/AllPoliciesController.getFilterOptions";

jest.mock(
	"@salesforce/apex/AllPoliciesController.getPage",
	() => ({ default: jest.fn() }),
	{ virtual: true }
);
jest.mock(
	"@salesforce/apex/AllPoliciesController.getTotal",
	() => ({ default: jest.fn() }),
	{ virtual: true }
);
jest.mock(
	"@salesforce/apex/AllPoliciesController.getFilterOptions",
	() => ({ default: jest.fn() }),
	{ virtual: true }
);

const OPTIONS = {
	carriers: [{ label: "Quálitas", value: "a0Q000000000001" }],
	statuses: [
		{ label: "Vigente", value: "Vigente" },
		{ label: "Cancelado", value: "Cancelado" }
	],
	picklistLabels: {
		Ramo__c: { Automoviles: "Automóviles" },
		PremiumFrequency: { Mensual: "Mensual" },
		Status: { Vigente: "Vigente" }
	}
};

/** Página de pólizas con Id y número consecutivos a partir de start. */
function policies(start, count) {
	return Array.from({ length: count }, (unused, index) => {
		const n = start + index;
		return {
			Id: `0YT${String(n).padStart(12, "0")}`,
			Name: `POL-${n}`,
			Aseguradora__r: { Name: "Quálitas" },
			Ramo__c: "Automoviles",
			NameInsured: { Name: `Asegurado ${n}` },
			PremiumFrequency: "Mensual",
			EffectiveDate: "2026-01-15T06:00:00.000Z",
			ExpirationDate: "2027-01-15T06:00:00.000Z",
			PremiumAmount: 12345.5,
			Status: "Vigente",
			insuredSubject__c: `Bien ${n}`,
			CreatedDate: "2026-11-01T18:00:00.000Z"
		};
	});
}

function flushPromises() {
	// eslint-disable-next-line @lwc/lwc/no-async-operation
	return new Promise((resolve) => setTimeout(resolve, 0));
}

async function settle() {
	for (let i = 0; i < 5; i++) {
		// eslint-disable-next-line no-await-in-loop
		await flushPromises();
	}
}

async function mount() {
	const element = createElement("c-all-policies", { is: AllPolicies });
	document.body.appendChild(element);
	await settle();
	return element;
}

function table(element) {
	return element.shadowRoot.querySelector("lightning-datatable");
}

describe("c-all-policies", () => {
	beforeEach(() => {
		getFilterOptions.mockResolvedValue(OPTIONS);
		getTotal.mockResolvedValue(3022);
		getPage.mockResolvedValue(policies(1, PAGE_SIZE));
	});

	afterEach(() => {
		while (document.body.firstChild) {
			document.body.removeChild(document.body.firstChild);
		}
		jest.clearAllMocks();
		jest.useRealTimers();
	});

	it("muestra el total real, lo cargado y las filas con formato", async () => {
		const element = await mount();

		const title = element.shadowRoot.querySelector(".total").textContent;
		expect(title).toBe("3,022 pólizas");
		expect(element.shadowRoot.querySelector(".loaded").textContent).toContain(
			"200 cargadas"
		);
		const rows = table(element).data;
		expect(rows).toHaveLength(PAGE_SIZE);
		expect(rows[0].policyUrl).toBe(
			`/lightning/r/InsurancePolicy/${rows[0].Id}/view`
		);
		expect(rows[0].ramoLabel).toBe("Automóviles");
		expect(rows[0].premiumLabel).toBe("$12,345.50");
		expect(rows[0].effectiveLabel).toMatch(/^\d{2}\/\d{2}\/2026$/);
		expect(table(element).enableInfiniteLoading).toBe(true);
		expect(getPage).toHaveBeenCalledWith(
			expect.objectContaining({
				sortField: "Name",
				sortDirection: "ASC",
				cursorValue: null,
				cursorId: null,
				pageSize: PAGE_SIZE
			})
		);
	});

	it("pide la página siguiente con el cursor de la última fila y para al llegar una incompleta", async () => {
		const element = await mount();
		getPage.mockResolvedValueOnce(policies(PAGE_SIZE + 1, 3));

		table(element).dispatchEvent(new CustomEvent("loadmore"));
		await settle();

		const last = policies(PAGE_SIZE, 1)[0];
		expect(getPage).toHaveBeenLastCalledWith(
			expect.objectContaining({ cursorValue: last.Name, cursorId: last.Id })
		);
		expect(table(element).data).toHaveLength(PAGE_SIZE + 3);
		expect(table(element).enableInfiniteLoading).toBe(false);
		expect(element.shadowRoot.querySelector(".loaded").textContent).toContain(
			"todas a la vista"
		);

		table(element).dispatchEvent(new CustomEvent("loadmore"));
		await settle();
		expect(getPage).toHaveBeenCalledTimes(2);
	});

	it("ordena en el servidor y reinicia la carga", async () => {
		const element = await mount();
		getPage.mockClear();

		table(element).dispatchEvent(
			new CustomEvent("sort", {
				detail: { fieldName: "premiumLabel", sortDirection: "desc" }
			})
		);
		await settle();

		expect(getPage).toHaveBeenCalledTimes(1);
		expect(getPage).toHaveBeenCalledWith(
			expect.objectContaining({
				sortField: "PremiumAmount",
				sortDirection: "DESC",
				cursorId: null
			})
		);
		expect(table(element).sortedBy).toBe("premiumLabel");
		expect(table(element).sortedDirection).toBe("desc");
	});

	it("filtra por aseguradora y estado, busca con espera y limpia", async () => {
		const element = await mount();
		getPage.mockClear();
		getTotal.mockClear();

		const carrier = element.shadowRoot.querySelector(".carrier-filter");
		carrier.dispatchEvent(
			new CustomEvent("change", { detail: { value: "a0Q000000000001" } })
		);
		await settle();
		const status = element.shadowRoot.querySelector(".status-filter");
		status.dispatchEvent(
			new CustomEvent("change", { detail: { value: "Vigente" } })
		);
		await settle();

		expect(getTotal).toHaveBeenLastCalledWith({
			searchTerm: null,
			carrierId: "a0Q000000000001",
			status: "Vigente"
		});
		expect(carrier.options).toHaveLength(2);

		jest.useFakeTimers();
		getPage.mockClear();
		const search = element.shadowRoot.querySelector("lightning-input");
		search.dispatchEvent(
			new CustomEvent("change", { detail: { value: " POL-1" } })
		);
		expect(getPage).not.toHaveBeenCalled();
		jest.advanceTimersByTime(SEARCH_DELAY_MS);
		jest.useRealTimers();
		await settle();
		expect(getPage).toHaveBeenCalledWith(
			expect.objectContaining({ searchTerm: "POL-1", status: "Vigente" })
		);

		element.shadowRoot.querySelector(".clear-button").click();
		await settle();
		expect(getTotal).toHaveBeenLastCalledWith({
			searchTerm: null,
			carrierId: null,
			status: null
		});
	});

	it("enseña un mensaje legible si el servidor falla", async () => {
		getPage.mockRejectedValue({
			body: { message: "No se pudieron cargar las pólizas: sin acceso" }
		});
		const element = await mount();

		const error = element.shadowRoot.querySelector(".error");
		expect(error.textContent).toContain("sin acceso");
		expect(table(element).enableInfiniteLoading).toBe(false);
	});

	it("avisa cuando no hay pólizas con esos filtros", async () => {
		getPage.mockResolvedValue([]);
		getTotal.mockResolvedValue(0);
		const element = await mount();

		expect(element.shadowRoot.querySelector(".empty")).not.toBeNull();
		expect(element.shadowRoot.querySelector(".total").textContent).toBe(
			"0 pólizas"
		);
	});
});
