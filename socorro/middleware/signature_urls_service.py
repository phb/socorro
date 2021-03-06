import logging

from socorro.middleware.service import DataAPIService

logger = logging.getLogger("webapi")


class SignatureURLs(DataAPIService):

    service_name = "signature_urls"
    uri = "/signatureurls/(.*)"

    def __init__(self, config):
        super(SignatureURLs, self).__init__(config)
        logger.debug('SignatureURLs service __init__')

    def get(self, *args):
        params = self.parse_query_string(args[0])

        module = self.get_module(params)

        impl = module.SignatureURLs(config=self.context)

        return impl.get(**params)
