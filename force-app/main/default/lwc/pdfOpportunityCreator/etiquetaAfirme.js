// Las cotizaciones de auto de Afirme traen el producto (ELITE, ELITE VERDE, PREMIUM, PREMIUM VERDE) como imagen, no como
// texto: se reconoce por la forma de sus renglones. Un renglón es ELITE o PREMIUM y, si hay otro debajo, es VERDE.

// Renglones de tinta oscura de una imagen: [{ alto, ancho }]; null si no es un letrero negro sobre fondo claro.
function renglones(img) {
	const { width, height, data } = img;
	if (!data || width < 100 || width > 400 || height < 30 || height > 250) { return null; }
	const n = data.length / (width * height);
	if (n !== 3 && n !== 4) { return null; }
	const lista = [];
	let actual = null;
	for (let y = 0; y < height; y++) {
		let min = -1;
		let max = -1;
		for (let x = 0; x < width; x++) {
			const i = (y * width + x) * n;
			if (n === 4 && data[i + 3] < 128) { continue; }
			const claro = Math.min(data[i], data[i + 1], data[i + 2]);
			const oscuro = Math.max(data[i], data[i + 1], data[i + 2]);
			// Con color no es el letrero.
			if (oscuro - claro > 60) { return null; }
			if (oscuro < 110) { if (min < 0) { min = x; } max = x; }
		}
		if (min < 0) { actual = null; continue; }
		if (!actual) { actual = { alto: 0, min, max }; lista.push(actual); }
		actual.alto++;
		actual.min = Math.min(actual.min, min);
		actual.max = Math.max(actual.max, max);
	}
	return lista.filter((r) => r.alto >= 8).map((r) => ({ alto: r.alto, ancho: r.max - r.min + 1 }));
}

// ELITE mide unas 3.6 veces su alto; PREMIUM, casi el doble.
export function productoDeImagen(img) {
	const r = renglones(img);
	if (!r || r.length < 1 || r.length > 2) { return ""; }
	const razon = r[0].ancho / r[0].alto;
	if (razon < 2.8 || razon > 9) { return ""; }
	return (razon < 5 ? "ELITE" : "PREMIUM") + (r.length === 2 ? " VERDE" : "");
}

// Producto de la cotización de Afirme según las imágenes de su primera página; "" si no se reconoce.
export async function productoAfirme(pdf, OPS) {
	const page = await pdf.getPage(1);
	const ops = await page.getOperatorList();
	const nombres = ops.argsArray.filter((a, i) => ops.fnArray[i] === OPS.paintImageXObject && a && a[1] <= 400).map((a) => a[0]);
	for (const nombre of nombres) {
		// eslint-disable-next-line no-await-in-loop
		const img = await new Promise((resolve) => {
			(String(nombre).startsWith("g_") ? page.commonObjs : page.objs).get(nombre, resolve);
		});
		const producto = img ? productoDeImagen(img) : "";
		if (producto) { return producto; }
	}
	return "";
}
