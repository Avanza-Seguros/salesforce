@isTest
global with sharing class BanxicoHttpMock implements HttpCalloutMock {
    global HTTPResponse respond(HTTPRequest req) {

        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(200);

        String endpoint = req.getEndpoint();
        String body;

        if (endpoint.contains('SF63528')) {
            body = '{"bmx":{"series":[{"idSerie":"SF63528","datos":[' +
                   '{"fecha":"01/01/2026","dato":"17.10"},' +
                   '{"fecha":"02/01/2026","dato":"17.20"}]}]}}';
        }
        else if (endpoint.contains('SP68257')) {
            body = '{"bmx":{"series":[{"idSerie":"SP68257","datos":[' +
                   '{"fecha":"01/01/2026","dato":"8.90"},' +
                   '{"fecha":"02/01/2026","dato":"8.95"}]}]}}';
        }
        else {
            res.setStatusCode(404);
            body = '{"error":"Serie no soportada en mock"}';
        }

        res.setBody(body);
        return res;
    }
}