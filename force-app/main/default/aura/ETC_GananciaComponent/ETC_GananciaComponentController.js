({
    onInitHandler : function(component, event, helper) {
        try {
            Promise.all([
                helper.getGananciaActual(component).then(gananciaActual => {
                    component.set('v.comisionActual',gananciaActual);
                }),
                helper.getGananciaAnterior(component).then(gananciaAnterior => {
                    component.set('v.comisionAnterior', gananciaAnterior);
                })
            ]).then(()=>{
                component.set('v.isLoading',false);
            }).catch(error=>{
                console.log(error);
                component.set('v.isLoading',false);
            });
        } catch (error) {
            console.log(error);
        }
        
    }
})