({
	getUSD : function(component, event, helper) {
		return new Promise(
            $A.getCallback(function(resolve, reject) {
                console.log('getOrderItems');
                var recordId = component.get('v.recordId');
                var action = component.get("c.getUSD");
                
                action.setCallback(this, function(response) {
                    if(response.getState() === 'SUCCESS') {
                        try {
                            console.log('EXITOSO');
                            var result = response.getReturnValue();
                            // console.log(result);
                            // console.log(result);
                            component.set('v.usdChange', result);
                            resolve();
                        } catch (error) {
                            console.log(error);
                            reject(error);
                            // this.showToast('error','Mensaje',error);
                        }
                    }else{
                        console.log(response.getState());
                        console.log(response.getError());
                        // this.showToast('error','Mensaje',response.getError());
                        reject(response.getError());
                    }
                    
                });
                $A.enqueueAction(action); 
            })
        );
	},

	getUDI : function(component) {
		return new Promise(
            $A.getCallback(function(resolve, reject) {
                console.log('getOrderItems');
                var recordId = component.get('v.recordId');
                var action = component.get("c.getUDI");
                
                action.setCallback(this, function(response) {
                    if(response.getState() === 'SUCCESS') {
                        try {
                            console.log('EXITOSO');
                            var result = response.getReturnValue();
                            // console.log(result);
                            // console.log(result);
                            component.set('v.udiChange', result);
                            resolve();
                        } catch (error) {
                            console.log(error);
                            reject(error);
                            // this.showToast('error','Mensaje',error);
                        }
                    }else{
                        console.log(response.getState());
                        console.log(response.getError());
                        // this.showToast('error','Mensaje',response.getError());
                        reject(response.getError());
                    }
                    
                });
                $A.enqueueAction(action); 
            })
        );
	},


	showToast: function (type, title, message) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type": type,
            "title": title,
            "message": message
        });
        toastEvent.fire();
    },
    showToastSuccess: function (title, message) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type": 'success',
            "title": title,
            "message": message
        });
        toastEvent.fire();
    },
    showToastError: function (title, message) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type": 'error',
            "title": title,
            "message": message
        });
        toastEvent.fire();
    },
    showToastWarning: function (title, message) {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type": 'warning',
            "title": title,
            "message": message
        });
        toastEvent.fire();
    },
})