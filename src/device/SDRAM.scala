package ysyx

import chisel3._
import chisel3.util._
import chisel3.experimental.Analog

import freechips.rocketchip.amba.axi4._
import freechips.rocketchip.amba.apb._
import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.util._

class SDRAMIO extends Bundle {
  val clk = Output(Bool())
  val cke = Output(Bool())
  val cs  = Output(Bool())
  val ras = Output(Bool())
  val cas = Output(Bool())
  val we  = Output(Bool())
  val a   = Output(UInt(13.W))
  val ba  = Output(UInt(2.W))
  val dqm = Output(UInt(2.W))
  val dq  = Analog(16.W)
}

// 32-bit interface for AXI SDRAM controller (sdram_top_axi.v)
// Uses 32-bit data path with 2 chip selects and 4-bit dqm
// Port names must exactly match sdram_top_axi.v
class SDRAMIO_AXI extends Bundle {
  val sdram_clk = Output(Bool())
  val sdram_cke = Output(Bool())
  val sdram_cs  = Output(UInt(2.W))   // 2 chip selects for 32-bit
  val sdram_ras = Output(Bool())
  val sdram_cas = Output(Bool())
  val sdram_we  = Output(Bool())
  val sdram_a   = Output(UInt(13.W))
  val sdram_ba  = Output(UInt(2.W))
  val sdram_dqm = Output(UInt(4.W))   // 4-bit mask for 32-bit
  val sdram_dq  = Analog(32.W)        // 32-bit data
}

class sdram_top_axi extends BlackBox {
  val io = IO(new Bundle {
    val clock = Input(Clock())
    val reset = Input(Bool())
    val in = Flipped(new AXI4Bundle(AXI4BundleParameters(addrBits = 32, dataBits = 32, idBits = 4)))
    val sdram_clk = Output(Bool())
    val sdram_cke = Output(Bool())
    val sdram_cs  = Output(UInt(2.W))
    val sdram_ras = Output(Bool())
    val sdram_cas = Output(Bool())
    val sdram_we  = Output(Bool())
    val sdram_a   = Output(UInt(13.W))
    val sdram_ba  = Output(UInt(2.W))
    val sdram_dqm = Output(UInt(4.W))
    val sdram_dq  = Analog(32.W)
  })
}

class sdram_top_apb extends BlackBox {
  val io = IO(new Bundle {
    val clock = Input(Clock())
    val reset = Input(Bool())
    val in = Flipped(new APBBundle(APBBundleParameters(addrBits = 32, dataBits = 32)))
    val sdram = new SDRAMIO
  })
}

class sdram extends BlackBox {
  val io = IO(Flipped(new SDRAMIO))
}

class sdramChisel extends RawModule {
  val io = IO(Flipped(new SDRAMIO))
}

// 32-bit SDRAM model for AXI controller (uses two 16-bit chips)
class sdram32 extends BlackBox {
  val io = IO(Flipped(new SDRAMIO_AXI))
}

class AXI4SDRAM(address: Seq[AddressSet])(implicit p: Parameters) extends LazyModule {
  val beatBytes = 4
  val node = AXI4SlaveNode(Seq(AXI4SlavePortParameters(
    Seq(AXI4SlaveParameters(
        address       = address,
        executable    = true,
        supportsWrite = TransferSizes(1, beatBytes),
        supportsRead  = TransferSizes(1, beatBytes),
        interleavedId = Some(0))
    ),
    beatBytes  = beatBytes)))

  lazy val module = new Impl
  class Impl extends LazyModuleImp(this) {
    val (in, _) = node.in(0)
    val sdram_bundle = IO(new SDRAMIO_AXI)

    val msdram = Module(new sdram_top_axi)
    msdram.io.clock := clock
    msdram.io.reset := reset.asBool
    msdram.io.in <> in
    // Connect SDRAM ports individually
    sdram_bundle.sdram_clk  := msdram.io.sdram_clk
    sdram_bundle.sdram_cke  := msdram.io.sdram_cke
    sdram_bundle.sdram_cs   := msdram.io.sdram_cs
    sdram_bundle.sdram_ras  := msdram.io.sdram_ras
    sdram_bundle.sdram_cas  := msdram.io.sdram_cas
    sdram_bundle.sdram_we   := msdram.io.sdram_we
    sdram_bundle.sdram_a    := msdram.io.sdram_a
    sdram_bundle.sdram_ba   := msdram.io.sdram_ba
    sdram_bundle.sdram_dqm  := msdram.io.sdram_dqm
    sdram_bundle.sdram_dq   <> msdram.io.sdram_dq
  }
}

class APBSDRAM(address: Seq[AddressSet])(implicit p: Parameters) extends LazyModule {
  val node = APBSlaveNode(Seq(APBSlavePortParameters(
    Seq(APBSlaveParameters(
      address       = address,
      executable    = true,
      supportsRead  = true,
      supportsWrite = true)),
    beatBytes  = 4)))

  lazy val module = new Impl
  class Impl extends LazyModuleImp(this) {
    val (in, _) = node.in(0)
    val sdram_bundle = IO(new SDRAMIO)

    val msdram = Module(new sdram_top_apb)
    msdram.io.clock := clock
    msdram.io.reset := reset.asBool
    msdram.io.in <> in
    sdram_bundle <> msdram.io.sdram
  }
}
