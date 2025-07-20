from pyparsing import Word, alphanums, OneOrMore, Group, Suppress, Optional, pythonStyleComment, ParserElement
import logging
from logic import Logic
from IPython.core.magic import register_line_magic

ParserElement.set_default_whitespace_chars(' \t')  

log = logging.getLogger(__name__)

class DSLGraph:
    def __init__(self, G):
        # Initialize values for the DSLGraph
        self.graph = G
        self.mac_only = False

        self.queries = []
        self.aliases = {}

        self.logic = Logic(G=G)

        self._build_parser()
        self.keywords = ("command", "node", "edge")
        
        # Blacklist of words that should not be resolved as aliases in commands
        self.arg_blacklist = {"files", "subject", "objects", "special", "trusted", "strongest", "process", "ipc", "subject", "files"}

    def get_keywords(self):
        return self.keywords

    def _build_parser(self):
        # Build the pyparsing parser for the DSL.
        word = Word(alphanums + "_-:.")  
        # Set parsing rules
        node_stmt = Suppress("node") + word("alias") + word("real_name")
        edge_stmt = Suppress("edge") + word("src") + word("dst")
        command_stmt = Suppress("command") + word("cmd") + Optional(OneOrMore(word), default=[])("args")

        stmt = node_stmt.setParseAction(self._handle_node) | \
               edge_stmt.setParseAction(self._handle_edge) | \
               command_stmt.setParseAction(self._handle_command)

        self.parser = stmt.ignore(pythonStyleComment)
    
    def parse_line(self, line): 
        try:
            self.parser.parse_string(line, parse_all=True)
        except Exception as e:
            log.error(f"Failed to parse line: {line}\nError: {e}")

    def parse_file(self, filename):
        # Parse a DSL file by line
        with open(filename) as f:
            for lineno, line in enumerate(f, start=1):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                try:
                    self.parser.parse_string(line, parse_all=True)
                except Exception as e:
                    log.error(f"Failed to parse line {lineno}: {line}\nError: {e}")

    def _handle_node(self, tokens):
        # Handle node variables in files
        alias, real_name = tokens.alias, tokens.real_name
        self.aliases[alias] = real_name

    def _handle_edge(self, tokens):
        # Handle edge variables in file
        src = self.resolve(tokens.src)
        dst = self.resolve(tokens.dst)

    def _handle_command(self, tokens):
        # Handle commands in the dsl
        cmd = tokens.cmd
        args = []
        for arg in tokens.args:
            # Don't resolve numbers
            if arg.isdigit():
                args.append(arg)
            # Don't resolve if argument contains any blacklisted keyword
            elif any(blacklisted in arg for blacklisted in self.arg_blacklist):
                args.append(arg)
            # Resolve everything else as aliases
            else:
                args.append(self.resolve(arg))
        
        handler = None
        for cmd_entry in self.logic.get_commands():
            if cmd_entry['name'] == cmd:
                handler = cmd_entry['handler']
                break
        if handler:
            handler(args)
        else:
            log.error(f"Unknown command: {cmd}")

    def resolve(self, name):
        # Resolve an alias to its real node name
        if name in self.aliases:
            return self.aliases[name]
        else:
            raise ValueError(f"Unknown alias: {name}. Available aliases: {list(self.aliases.keys())}")
