({
	onInitHandler : function(component, event, helper) {
		console.log('onInitHandler');
		component.set('v.isLoading', true);
		Promise.all([
			helper.getUSD(component),
			helper.getUDI(component)
		]).then(()=>{
			component.set('v.isLoading', false);
		}).catch((error)=>{
			console.log(error);
			helper.showToastError('Error', 'Ocurrio un error verificalo con tu administrador');
		});
	},

	// getData : function(component, event, helper) {

	// 	Promise.all([
	// 		helper.getUSD(),
	// 		helper.getUDI()
	// 	]);
	// }
})