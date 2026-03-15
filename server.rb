require "webrick"
require "listen"

PORT = 3000
DIR = File.join(__dir__, "public")

# Track connected SSE clients
clients = []
clients_mutex = Mutex.new

# File watcher — triggers reload on any change
listener = Listen.to(DIR, only: /\.(html|css|js|jpg|png|svg)$/, wait_for_delay: 0.2) do |modified, added, removed|
  changed = [*modified, *added, *removed].map { |f| File.basename(f) }
  puts "\e[33m~ changed: #{changed.join(", ")}\e[0m"

  clients_mutex.synchronize do
    clients.each do |client|
      client << "data: reload\n\n" rescue nil
    end
    clients.reject!(&:closed?)
  end
end
listener.start

# Server
server = WEBrick::HTTPServer.new(Port: PORT, DocumentRoot: DIR, Logger: WEBrick::Log.new($stdout, WEBrick::Log::INFO))

# SSE endpoint for auto-reload
server.mount_proc "/reload" do |_req, res|
  res["Content-Type"] = "text/event-stream"
  res["Cache-Control"] = "no-cache"
  res["Connection"] = "keep-alive"
  res["Access-Control-Allow-Origin"] = "*"

  rd, wr = IO.pipe
  clients_mutex.synchronize { clients << wr }

  res.body = rd
  res.chunked = true
end

# Inject auto-reload script into HTML responses
original_do_GET = WEBrick::HTTPServlet::FileHandler.instance_method(:do_GET)

WEBrick::HTTPServlet::FileHandler.prepend(Module.new do
  def do_GET(req, res)
    super
    if res["Content-Type"]&.include?("text/html") && res.body.is_a?(String)
      reload_script = <<~JS
        <script>
          (function() {
            var es = new EventSource('/reload');
            es.onmessage = function(e) {
              if (e.data === 'reload') location.reload();
            };
            es.onerror = function() {
              setTimeout(function() { location.reload(); }, 1000);
            };
          })();
        </script>
      JS
      res.body = res.body.sub("</body>", reload_script + "</body>")
      res["Content-Length"] = res.body.bytesize.to_s
    end
  end
end)

trap("INT") { listener.stop; server.shutdown }
trap("TERM") { listener.stop; server.shutdown }

puts "\n\e[1;32m  Linda Haar & Nagelstylist\e[0m"
puts "  \e[36mhttp://localhost:#{PORT}\e[0m"
puts "  \e[90mAuto-reload actief — wijzig een bestand en de browser ververst automatisch\e[0m\n\n"

server.start
