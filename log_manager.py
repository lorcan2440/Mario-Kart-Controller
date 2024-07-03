import logging
import time

class MicrosecondFormatter(logging.Formatter):
    """
    A custom formatter to include microseconds in log records.
    """
    def formatTime(self, record, datefmt=None):
        """
        Override formatTime to add microseconds.
        """
        # Create a timestamp using the original record's creation time
        ct = self.converter(record.created)
        if datefmt:
            # If datefmt is specified, use it, but add microseconds
            s = time.strftime(datefmt, ct) + ".{:06d}".format(record.msecs * 1000)
        else:
            # Default format includes the full date, time, and microseconds
            s = time.strftime("%Y-%m-%d %H:%M:%S", ct) + ".{:06d}".format(record.msecs * 1000)
        return s

# Set up logging with the custom formatter
logging.basicConfig(format='%(asctime)s %(message)s', filename='stream_log.log',
    filemode='a', encoding='utf-8', level=logging.DEBUG)
console = logging.StreamHandler()
console.setLevel(logging.INFO)

# Use the custom formatter
formatter = MicrosecondFormatter('%(name)-12s: %(levelname)-8s %(message)s', '%m/%d/%Y %I:%M:%S %p')
console.setFormatter(formatter)
logging.getLogger().addHandler(console)
logging.captureWarnings(True)
log_server = logging.getLogger('Python Server')