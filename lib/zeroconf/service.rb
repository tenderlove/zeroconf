# frozen_string_literal: true

module ZeroConf
  class Service
    attr_reader :service, :service_port, :hostname, :service_interfaces,
      :service_name, :qualified_host, :text

    def initialize service, service_port, hostname = Socket.gethostname, service_interfaces: ZeroConf.service_interfaces, text: [""]
      @service = service
      @service_port = service_port
      @hostname = hostname
      @service_interfaces = service_interfaces
      @service_name = "#{hostname}.#{service}"
      @qualified_host = "#{hostname}.local."
      @text = text
      @rd, @wr = IO.pipe
    end

    def announcement
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional service_name, 60, MDNS::Announce::IN::SRV.new(0, 0, service_port, qualified_host)

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host,
            60,
            MDNS::Announce::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host,
            60,
            MDNS::Announce::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name,
          60,
          MDNS::Announce::IN::TXT.new(*@text)
      end

      msg.add_answer service,
        60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service_name))

      msg
    end

    def disconnect_msg
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional service_name, 0, Resolv::DNS::Resource::IN::SRV.new(0, 0, service_port, qualified_host)

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host,
            0,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host,
            0,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name,
          0,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg.add_answer service,
        0,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service_name))

      msg
    end

    include Utils

    def stop
      @wr.write "x"
      @wr.close
    end

    def start
      sock = open_ipv4 Addrinfo.new(Socket.sockaddr_in(Resolv::MDNS::Port, Socket::INADDR_ANY)), Resolv::MDNS::Port

      sockets = [sock, @rd]

      msg = announcement

      # announce
      multicast_send(sock, msg.encode)

      loop do
        readers, = IO.select(sockets, [], [])
        next unless readers

        readers.each do |reader|
          return if reader == @rd

          buf, from = reader.recvfrom 2048
          msg = Resolv::DNS::Message.decode(buf)

          has_flags = (buf.getbyte(3) << 8 | buf.getbyte(2)) != 0

          msg.question.each do |name, type|
            class_type = type::ClassValue & ~MDNS_CACHE_FLUSH

            break unless class_type == 1 || class_type == 255

            unicast = type::ClassValue & PTR::MDNS_UNICAST_RESPONSE > 0

            qn = name.to_s + "."

            res = case qn
            when DISCOVERY_NAME
              break if has_flags

              if unicast
                dnssd_unicast_answer
              else
                dnssd_multicast_answer
              end
            when service
              if unicast
                service_unicast_answer
              else
                service_multicast_answer
              end
            when service_name
              if unicast
                service_instance_unicast_answer
              else
                service_instance_multicast_answer
              end
            when qualified_host
              if unicast
                name_answer_unicast
              else
                name_answer_multicast
              end
            else
              #p [:QUERY2, type, type::ClassValue, name]
            end

            next unless res

            if unicast
              unicast_send reader, res.encode, from
            else
              multicast_send reader, res.encode
            end
          end

          # only yield replies to this question
        end
      end
    ensure
      multicast_send sock, disconnect_msg.encode
      sockets.map(&:close)
    end

    private

    def service_instance_unicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host,
            10,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host,
            10,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name,
          10,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end
      msg.add_answer service_name, 10, Resolv::DNS::Resource::IN::SRV.new(0, 0, service_port, qualified_host)
      msg.add_question service_name, ZeroConf::MDNS::Announce::IN::SRV

      msg
    end

    def service_unicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional service_name, 10, Resolv::DNS::Resource::IN::SRV.new(0, 0, service_port, qualified_host)

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host,
            10,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host,
            10,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name,
          10,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg.add_answer service,
        10,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service_name))

      msg.add_question service, ZeroConf::PTR

      msg
    end

    def dnssd_unicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_answer DISCOVERY_NAME, 10,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service))

      msg.add_question DISCOVERY_NAME, ZeroConf::PTR
      msg
    end

    def dnssd_multicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_answer DISCOVERY_NAME, 60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service))
      msg
    end

    def service_multicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional service_name, 60, Resolv::DNS::Resource::IN::SRV.new(0, 0, service_port, qualified_host)

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host,
            60,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host,
            60,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name,
          60,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg.add_answer service,
        60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service_name))

      msg
    end

    def service_instance_multicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_answer service_name, 60, Resolv::DNS::Resource::IN::SRV.new(0, 0, service_port, qualified_host)

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host,
            60,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host,
            60,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name,
          60,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg
    end

    def name_answer_unicast
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      first = true

      service_interfaces.each do |iface|
        if first
          if iface.addr.ipv4?
            msg.add_answer qualified_host,
              10,
              Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
          else
            msg.add_answer s.qualified_host,
              10,
              Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
          end
          first = false
        else
          if iface.addr.ipv4?
            msg.add_additional qualified_host,
              10,
              Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
          else
            msg.add_additional qualified_host,
              10,
              Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
          end
        end
      end

      msg.add_question qualified_host, ZeroConf::MDNS::Announce::IN::A

      if @text
        msg.add_additional service_name,
          10,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg
    end

    def name_answer_multicast
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      first = true

      service_interfaces.each do |iface|
        if first
          if iface.addr.ipv4?
            msg.add_answer qualified_host,
              60,
              Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
          else
            msg.add_answer s.qualified_host,
              60,
              Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
          end
          first = false
        else
          if iface.addr.ipv4?
            msg.add_additional qualified_host,
              60,
              Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
          else
            msg.add_additional qualified_host,
              60,
              Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
          end
        end
      end

      if @text
        msg.add_additional service_name,
          60,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg
    end
  end
end
